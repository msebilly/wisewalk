import Foundation
import SwiftData

/// 账本的**唯一**写入口。
///
/// 「只增不改不删」这条纪律如果散落在各个界面里就守不住，
/// 所以所有写操作收口到这里。界面层不许直接 `context.insert(PracticeSession…)`。
///
/// 标注 `@MainActor` 是因为 `ModelContext` 不是 Sendable，必须固定在一个执行域上。
/// v1 的写入量（一天几十笔）远达不到需要后台上下文的程度。
@MainActor
final class DayLedger {
    private let context: ModelContext
    private let deviceName: String

    init(context: ModelContext, deviceName: String) {
        self.context = context
        self.deviceName = deviceName
    }

    // MARK: - 写

    /// 记一笔并**立即落盘**。绝大多数场合用这个。
    ///
    /// - Parameter id: 预生成编号。崩溃恢复时传入草稿里的编号，
    ///   本方法会先查重，已入账则直接返回既有记录，不会重复计数。
    /// - Parameter onDay: 手动补记到**指定历史日期**时传入该日的 dayKey；为 nil 时按
    ///   `at:`/`dayStartHour`/`timeZone` 推导当天（现有行为不变）。
    ///   刻意与 `at:` 分开：§6.4 规定补记的 `dayKey` 为**所选日期**，而 `createdAt`
    ///   始终是**真实写入时刻**、`tzOffsetMinutes` 为**当前**偏移。「功课发生在哪天」
    ///   与「这条何时写下」是两件事，若靠回拨 `at:` 来补记，会连带篡改 createdAt
    ///   （快照去重排序与第 3 卷诊断都依赖它）与历史时区偏移。
    @discardableResult
    func record(
        item: PracticeItem,
        amount: Int,
        source: SessionSource,
        startedAt: Date,
        endedAt: Date? = nil,
        at now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current,
        id: UUID = UUID(),
        note: String? = nil,
        onDay: Int? = nil
    ) throws -> PracticeSession {
        let session = try stage(
            item: item, amount: amount, source: source,
            startedAt: startedAt, endedAt: endedAt, at: now,
            dayStartHour: dayStartHour, timeZone: timeZone,
            id: id, note: note, onDay: onDay
        )
        try context.save()
        return session
    }

    /// 把一笔流水放进上下文但**不落盘**，由调用方决定何时 `save()`。
    ///
    /// 查重、dayKey 推导、时区落款与 `record` 完全一致——`record` 就是本方法加一句 save。
    ///
    /// 存在的唯一理由：`DraftStore.commit` 要让「写流水」与「删草稿」进**同一次 save**
    /// （§4.5 第 1 条）。**除此之外不要用它**——忘了 save 就等于用户的功课没记上，
    /// 而且不会有任何报错。
    @discardableResult
    func stage(
        item: PracticeItem,
        amount: Int,
        source: SessionSource,
        startedAt: Date,
        endedAt: Date? = nil,
        at now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current,
        id: UUID = UUID(),
        note: String? = nil,
        onDay: Int? = nil
    ) throws -> PracticeSession {
        if let existing = try fetch(sessionID: id) {
            return existing
        }

        let offset = DayKey.currentOffsetMinutes(at: now, timeZone: timeZone)
        let session = PracticeSession(
            id: id,
            item: item,
            dayKey: onDay ?? DayKey.make(from: now, tzOffsetMinutes: offset, dayStartHour: dayStartHour),
            tzOffsetMinutes: offset,
            amount: amount,
            startedAt: startedAt,
            endedAt: endedAt,
            source: source,
            deviceName: deviceName,
            note: note,
            createdAt: now
        )
        context.insert(session)
        return session
    }

    /// 撤销一笔：追加一笔等额负数的 `.adjustment`。**原记录纹丝不动。**
    ///
    /// 新记录落在**原记录的 dayKey** 上而不是今天——
    /// 撤销昨天的误记，不该让今天的账面莫名少一截。
    @discardableResult
    func revoke(
        _ session: PracticeSession,
        at now: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> PracticeSession {
        // 幂等键就是 note 里的 "revoke:<原记录 id>"。
        // 多设备同撤或崩溃重放会对同一笔重复调用本方法；若不查重，
        // 第二笔 -amount 会叠加，把同日其他真实流水一起吃掉，再被 clamp 掩盖成「归零」——
        // 用户真做过的功课就此凭空消失。故仿照 record() 先查重后追加。
        //
        // 与 sessions(on:) 同样按 dayKey 取库、内存里过滤：
        // #Predicate 穿透可选关系不稳，而一天流水至多几十条。
        let noteKey = "revoke:\(session.id.uuidString)"
        let key = session.dayKey
        let sameDay = try context.fetch(
            FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.dayKey == key })
        )
        if let existing = sameDay.first(where: { $0.source == .adjustment && $0.note == noteKey }) {
            return existing
        }

        let adjustment = PracticeSession(
            item: session.item,
            dayKey: session.dayKey,
            tzOffsetMinutes: session.tzOffsetMinutes,
            amount: -session.amount,
            startedAt: now,
            endedAt: now,
            source: .adjustment,
            deviceName: deviceName,
            note: "revoke:\(session.id.uuidString)",
            createdAt: now
        )
        context.insert(adjustment)
        try context.save()
        return adjustment
    }

    // MARK: - 读

    /// 某天某项的全部流水。
    ///
    /// 先按 dayKey 取库、再在内存里按定课项过滤，是刻意为之：
    /// `#Predicate` 穿透可选关系（`$0.item?.id == x`）在 SwiftData 上行为不稳，
    /// 而一天的流水至多几十条，内存过滤的代价可以忽略。
    ///
    /// `$0.item?.id == itemID` 会**排除 item == nil 的孤儿流水**：它们不进任何 per-item 统计，
    /// 故 `PracticeItem` 只能归档不能硬删，否则历史静默蒸发（详见 `PracticeSession.item`）。
    func sessions(on dayKey: Int, itemID: UUID) throws -> [PracticeSession] {
        let key = dayKey
        let sameDay = try context.fetch(
            FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.dayKey == key })
        )
        return sameDay.filter { $0.item?.id == itemID }
    }

    /// 某天某项的显示总数（负数已 clamp 到 0）。
    func total(on dayKey: Int, itemID: UUID) throws -> Int {
        LedgerMath.displayTotal(try sessions(on: dayKey, itemID: itemID))
    }

    /// 某天某项的账本原值（可能为负）。诊断与导出使用。
    func rawTotal(on dayKey: Int, itemID: UUID) throws -> Int {
        LedgerMath.rawTotal(try sessions(on: dayKey, itemID: itemID))
    }

    /// 该编号是否已入账。崩溃恢复前必查。
    func exists(sessionID: UUID) throws -> Bool {
        try fetch(sessionID: sessionID) != nil
    }

    // MARK: - 当日计划与圆满

    /// 只读地取某天的应做清单：合并该日**所有** `DaySnapshot` 得出 `DayPlan`，
    /// 无任何同日快照则返回 nil。**本方法绝不插入、修改或保存任何东西。**
    ///
    /// 这是月历等纯渲染路径唯一该走的门：翻看三个月前的某天不该凭空捏造一条快照，
    /// 断言用户当时「本该」做今年才新建的功课——那种伪造会同步到每台设备、永久留存。
    /// 派生视图做成值类型（`DayPlan`）而非回写源记录，正是为了根除这种「读一下就写库」。
    func existingPlan(for dayKey: Int) throws -> DayPlan? {
        let key = dayKey
        let existing = try context.fetch(
            FetchDescriptor<DaySnapshot>(predicate: #Predicate { $0.dayKey == key })
        )
        guard !existing.isEmpty else { return nil }
        return Self.merge(dayKey: dayKey, snapshots: existing)
    }

    /// 取某天的应做计划；该日尚无任何快照时才依 `activeItems` 生成并落库。
    ///
    /// **已存在快照里各项的目标绝不改写。** 用户今天把目标从 1000 调到 3000，
    /// 上个月那些标着圆满的日子不能因此变回未完成——那等于告诉他过去三十天白做了。
    ///
    /// `DaySnapshot` 没有唯一约束（CloudKit 不支持），两台设备可能各生成一条同日快照，
    /// 且「最早一条」未必**最全**：iPad 清早只登记了念佛，iPhone 稍后新增并修了打坐，
    /// 若只取最早一条，打坐会被判为当日无需完成而从清单上悄悄消失。
    /// 故**应做项取所有同日快照的并集**（CRDT G-Set，可交换、可结合、幂等），
    /// 按 `uuidString` 排序保证各设备产出逐位相同的数组、真正达成一致。
    ///
    /// 目标的取值：某项若已在最早快照里出现，最早那条的意见（哪怕是「没设目标」）为准，
    /// 守住「绝不回溯改写过去某天目标」的铁律；只有最早快照对某项**毫无意见**（并集新增项）时，
    /// 才采用「含该项的最早一条快照」的目标，同样按 `(createdAt, id)` 确定性解析。
    ///
    /// 合并结果是**派生视图**，不回写任何源快照：源快照**绝不删除**、各自保持原样，
    /// 每次读取重新合并即自愈，即便某条在整记录级 LWW 里输掉也不影响并集结果。
    ///
    /// 只有用户**真正打开/记录某天**、或按 §6.4 补记历史日期时才走本方法生成快照；
    /// 纯渲染请改用只读的 `existingPlan(for:)`。
    ///
    /// 代价（已知并接受）：已归档的功课当天可能多唠叨一次，
    /// 某天也可能在更全的信息同步进来后由圆满退回待完成。
    func plan(for dayKey: Int, activeItems: [PracticeItem]) throws -> DayPlan {
        if let existing = try existingPlan(for: dayKey) {
            return existing
        }

        let required = activeItems.filter { !$0.isArchived }
        var goals: [String: Int] = [:]
        for item in required {
            if let goal = item.dailyGoal, goal > 0 {
                goals[item.id.uuidString] = goal
            }
        }

        let snapshot = DaySnapshot(
            dayKey: dayKey,
            requiredItemIDs: required.map(\.id),
            goals: goals
        )
        context.insert(snapshot)
        try context.save()
        return DayPlan(dayKey: dayKey, requiredItemIDs: snapshot.requiredItemIDs, goals: goals)
    }

    /// 把同日多条快照合并成只读 `DayPlan`。纯函数，不碰上下文，故不会写库。
    private static func merge(dayKey: Int, snapshots: [DaySnapshot]) -> DayPlan {
        let ordered = snapshots.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }

        // 应做项：所有同日快照的并集，按 uuidString 排序确保跨设备逐位一致。
        var idSet = Set<UUID>()
        for snap in ordered { idSet.formUnion(snap.requiredItemIDs) }
        let mergedIDs = idSet.sorted { $0.uuidString < $1.uuidString }

        // 目标：逐项取「含该项的最早一条快照」的意见——
        // 已在最早快照里的项，其最早目标（含「无目标」）自然胜出，历史不被改写。
        var mergedGoals: [String: Int] = [:]
        for id in mergedIDs {
            guard let source = ordered.first(where: { $0.requiredItemIDs.contains(id) }) else { continue }
            if let goal = source.goals[id.uuidString] {
                mergedGoals[id.uuidString] = goal
            }
        }

        return DayPlan(dayKey: dayKey, requiredItemIDs: mergedIDs, goals: mergedGoals)
    }

    /// 依计划判定完成状态。**永不按当前设置实时重算。**
    ///
    /// `dayKey` 取自 `plan.dayKey`，不再单独传参——
    /// 从源头杜绝「拿甲日的清单去核对乙日的总数」这种静默错配。
    func fulfillment(
        of itemID: UUID,
        plan: DayPlan
    ) throws -> FulfillmentState {
        guard plan.requiredItemIDs.contains(itemID) else { return .notRequired }
        let total = try total(on: plan.dayKey, itemID: itemID)
        return LedgerMath.isFulfilled(total: total, goal: plan.goals[itemID.uuidString])
            ? .fulfilled
            : .pending
    }

    private func fetch(sessionID: UUID) throws -> PracticeSession? {
        let target = sessionID
        var descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.id == target }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
