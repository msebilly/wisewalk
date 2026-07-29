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

    /// 记一笔。
    ///
    /// - Parameter id: 预生成编号。崩溃恢复时传入草稿里的编号，
    ///   本方法会先查重，已入账则直接返回既有记录，不会重复计数。
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
        note: String? = nil
    ) throws -> PracticeSession {
        if let existing = try fetch(sessionID: id) {
            return existing
        }

        let offset = DayKey.currentOffsetMinutes(at: now, timeZone: timeZone)
        let session = PracticeSession(
            id: id,
            item: item,
            dayKey: DayKey.make(from: now, tzOffsetMinutes: offset, dayStartHour: dayStartHour),
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
        try context.save()
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

    // MARK: - 快照与圆满

    /// 取某天的应做清单快照；不存在则依 `activeItems` 生成并落库。
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
    /// 并集结果**仅在确有变化时**才回写到最早那条并保存，避免每次读取都无谓地扰动 CloudKit。
    /// 回写是派生结果而非权威：源快照**绝不删除**，故即便某次回写在整记录级 LWW 里输掉，
    /// 下次读取仍能从幸存的源快照重算并集而自愈。
    ///
    /// 代价（已知并接受）：已归档的功课当天可能多唠叨一次，
    /// 某天也可能在更全的信息同步进来后由圆满退回待完成。
    func snapshot(for dayKey: Int, activeItems: [PracticeItem]) throws -> DaySnapshot {
        let key = dayKey
        let existing = try context.fetch(
            FetchDescriptor<DaySnapshot>(predicate: #Predicate { $0.dayKey == key })
        )
        if !existing.isEmpty {
            let ordered = existing.sorted {
                ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
            }
            let earliest = ordered[0]

            // 应做项：所有同日快照的并集，按 uuidString 排序确保跨设备一致。
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

            // 仅在并集确有变化时才回写，避免无谓的 CloudKit churn。
            if earliest.requiredItemIDs != mergedIDs || earliest.goals != mergedGoals {
                earliest.requiredItemIDs = mergedIDs
                earliest.goals = mergedGoals
                try context.save()
            }
            return earliest
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
        return snapshot
    }

    /// 依快照判定完成状态。**永不按当前设置实时重算。**
    func fulfillment(
        of itemID: UUID,
        on dayKey: Int,
        snapshot: DaySnapshot
    ) throws -> FulfillmentState {
        guard snapshot.requiredItemIDs.contains(itemID) else { return .notRequired }
        let total = try total(on: dayKey, itemID: itemID)
        return LedgerMath.isFulfilled(total: total, goal: snapshot.goals[itemID.uuidString])
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
