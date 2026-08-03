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
        try context.saveOrRollback()
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
        try context.saveOrRollback()
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
        return Self.dedupedRevocations(sameDay.filter { $0.item?.id == itemID })
    }

    /// 这门课的「以往累计」眼下净剩多少。0 表示没记过，或者记过又撤了。
    ///
    /// §6.12 的注脚承诺「只需做一次」，但代码里**没有一行保证那个「一次」**——
    /// `submitMigrationTotal` 只是套了个备注的普通 `submit`，再点一次就是叠加。
    /// 他填错了回来重填，账面上凭空多出一份，方向是「多」，
    /// 量级是他一辈子功课的量级。
    ///
    /// 这个查询是给表单用的：一打开就把已记过的数摆在他眼前。
    /// **不是拦他**——这个 App 只在「圆满」一处替用户下判断，别处一律说出实情让他自己定。
    /// 真有第二本旧功课本要补，那也是他看着实情做的决定。
    ///
    /// ⚠️ **靠 `note` 认，不是靠「这门课的全部流水」**：后者会把他今天念的 108 声
    /// 也说成以往累计。
    ///
    /// ⚠️ **撤销要扣掉。** 记错了撤销之后，那句「已记过 3 小时」就成了假话，
    /// 而他正是撤销完回来重记的——被一句假话拦住最冤。撤销笔照例过
    /// `dedupedRevocations`，否则多台设备各撤一次会把净额扣成负数。
    func migratedTotal(itemID: UUID) throws -> Int {
        let note = ManualEntryViewModel.migrationNote
        let 迁移笔 = try context.fetch(
            FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.note == note })
        ).filter { $0.item?.id == itemID }
        guard !迁移笔.isEmpty else { return 0 }

        let 撤销键 = Set(迁移笔.map { "revoke:\($0.id.uuidString)" })
        let 撤销笔 = try context.fetch(
            FetchDescriptor<PracticeSession>(predicate: #Predicate<PracticeSession> { s in
                if let n = s.note { return 撤销键.contains(n) } else { return false }
            })
        )
        let 净额 = 迁移笔.reduce(0) { $0 + $1.amount }
            + Self.dedupedRevocations(撤销笔).reduce(0) { $0 + $1.amount }
        return max(0, 净额)
    }

    /// §5.7：把「多台设备各撤了同一笔」合并回一笔。
    ///
    /// `revoke` 的幂等键是 `note` 里的 `revoke:<原记录 id>`，可它**只查本机库**。
    /// 两台设备离线各撤同一笔 500，各自都查不到 → 各建一条 `amount: −500`、
    /// note 相同、**UUID 不同**的调整流水。CloudKit 合并后两条都在，于是
    /// `+500 +300 −500 −500 = −200`，`displayTotal` clamp 成 0，用户看到「今天 0 声」——
    /// 他真念的那 300 声就这么没了，**账面上还看不出哪儿错**。
    /// 方向是「丢」，且是最难察觉的一种：没有提示，数字只是变小了。
    ///
    /// 为什么不在写侧堵：那要靠「确定性 UUID + 框架把两条合成一条」，而
    /// **CloudKit 用不了 `@Attribute(.unique)`**（见 design-spec §5.2）。没有唯一约束，
    /// 两台设备各写一条就永远是两条。「事后清理一次」也不成立——只要还有第三台设备
    /// 可能上线补一条，清理就永远做不完。读侧去重是幂等的，任何时刻算出来都对。
    ///
    /// **收在这里，是因为 `total` / `rawTotal` / `roundCount` / 补记页流水全从这儿过。**
    /// 去重若分散写进每个读者，漏一个就是一处永久错账；第 2 卷有七次实测证据说明
    /// 「要说两遍的话，早晚有一处说错」。
    ///
    /// ⚠️ **分组键是「`revoke:` 前缀」+「完整 note 字符串」两个条件缺一不可。**
    /// 眼下 `revoke` 是全仓库唯一写 `.adjustment` 的地方、note 全带这个前缀，
    /// 所以「note 相同」看着等价；哪天有人加了第二个 `.adjustment` 写入口而 note 留空，
    /// 「note 相同」就会把**一整批不相干的调整塌成一条**。方向是「多」，量级不封顶。
    ///
    /// 「撤销那次撤销」不会被误伤：那一笔的 note 是 `revoke:<调整笔自己的 id>`，
    /// 与被它撤销的那笔不同组。（该路径今天还不存在——`ManualEntryView` 不给撤销行
    /// 配撤销按钮——但规则先站得住。）
    ///
    /// 保留哪一条按 `(createdAt, id.uuidString)` 定，让各设备显示同一条；
    /// 重复两笔 `amount` 本就相同，总数取哪条都对，这只为列表不看着像数据不一致。
    static func dedupedRevocations(_ sessions: [PracticeSession]) -> [PracticeSession] {
        var seen = Set<String>()
        var dropped = Set<UUID>()
        for s in sessions.sorted(by: {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }) {
            guard s.source == .adjustment,
                  let note = s.note, note.hasPrefix("revoke:") else { continue }
            if !seen.insert(note).inserted { dropped.insert(s.id) }
        }
        guard !dropped.isEmpty else { return sessions }
        return sessions.filter { !dropped.contains($0.id) }
    }

    /// 某天某项的显示总数（负数已 clamp 到 0）。
    func total(on dayKey: Int, itemID: UUID) throws -> Int {
        LedgerMath.displayTotal(try sessions(on: dayKey, itemID: itemID))
    }

    /// 某天某项的账本原值（可能为负）。诊断与导出使用。
    func rawTotal(on dayKey: Int, itemID: UUID) throws -> Int {
        LedgerMath.rawTotal(try sessions(on: dayKey, itemID: itemID))
    }

    /// 当日「做了几回」。计时类就是坐数。
    ///
    /// 撤销与修正走 `.adjustment`，它们是对既有一坐的更正，不是新的一坐；
    /// 负数流水更不该算。少数掉一坐比多数一坐好：多数出来的那一坐用户
    /// 对不上账，只会以为自己记错了。
    func roundCount(on dayKey: Int, itemID: UUID) throws -> Int {
        try sessions(on: dayKey, itemID: itemID)
            .filter { $0.amount > 0 && $0.source != .adjustment }
            .count
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

    /// 取某天的应做计划。**两条路都可能落库**：该日尚无快照时依 `activeItems` 生成一条；
    /// 已有快照时走 `appendLateArrivals`，把同步迟到的定课补成新的一条（无迟到项则不写）。
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
    /// - Parameter dayStartHour: **必须与算出 `dayKey` 的那把尺子一致。**
    ///   今日页的 `dayKey` 出自 `DayKey.today(dayStartHour:)`，就传同一个值；
    ///   补记页的 `selectedDayKey` 出自 `DayKey.fromCalendarDate`（日历格子，不减 dayStartHour），
    ///   就传 `0`。两把尺子混着比大小的后果，`ManualEntryViewModel.validate` 的注释里有实例。
    ///   **本参数没有默认值，就是要每个调用点自己说清楚用的哪把尺子**——
    ///   本仓库的 `dayStartHour: Int = 0` 已经害过一次：漏传一处就静默退回 0 点，没有任何测试会红。
    func plan(
        for dayKey: Int,
        activeItems: [PracticeItem],
        dayStartHour: Int,
        timeZone: TimeZone
    ) throws -> DayPlan {
        if let existing = try existingPlan(for: dayKey) {
            return try appendLateArrivals(
                to: existing,
                dayKey: dayKey,
                activeItems: activeItems,
                dayStartHour: dayStartHour,
                timeZone: timeZone
            )
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
        try context.saveOrRollback()
        return DayPlan(dayKey: dayKey, requiredItemIDs: snapshot.requiredItemIDs, goals: goals)
    }

    /// 该日已有快照时，把「那天开始之前就立好、只是数据晚到」的定课追加进去。
    ///
    /// **为什么需要它**（`docs/design-spec.md` §5.6 写侧，2026-07-30 定案走此路）：
    /// 换新机或重装后首次启动，CloudKit 可能一条定课都还没推下来。此时今日页一露面
    /// 就给今天定格了一条 `requiredItemIDs: []` 的快照，那天从此是「无课日」——
    /// `TodayViewModel.isRestDay` 的文档写明它**不计入分母，也不中断**，
    /// 等于替用户抹掉一天欠账；而且推给了所有设备，「已存在则沿用」意味着再也改不回来。
    ///
    /// **判据是「那天开始的时候这门课活没活着」，不是「本机是不是刚看见它」。**
    /// 后者分不清「同步迟到」与「用户今天刚立」：无差别并进来，
    /// 上午已显示圆满的那天会因为下午新立了一门课而退回未圆满。
    /// 用的是 `PracticeItem.activatedAt` 而不是 `createdAt`：一门课立于上月、上周归档、
    /// 今天下午恢复，按 `createdAt` 判就会被追加进今天，**把用户已挣到的圆满收回去**。
    /// `activatedAt` 记的是最近一次成为活跃状态的时刻，与它何时同步到本机无关，
    /// 正是要问的那句话。守卫见 `今天恢复的归档定课不会被追加进今天`
    /// 与 `昨天恢复的归档定课同步进来后仍要被追加`——这两条只差在恢复发生在哪一天。
    ///
    /// **⚠️ 本判据与初次定格不对称，是有意的，别去「修平」它。**
    /// 初次定格照收全部在册定课、包括今天刚立的（`plan` 的 else 分支，
    /// 守卫 `初次定格仍旧收下全部在册定课`）；本方法则把今天才激活的挡在外面。
    /// 于是「今天新立的课今天算不算数」取决于该日有没有别的设备先定过格。
    /// 曾经有人（包括写这段的人）把它解释成「新立的课按规矩从明天算起」——
    /// **仓库里没有这条规矩，那是编的。** 真正的理由是两个分支在答不同的问题：
    /// 初次定格反映用户此刻的意图，他正看着 App，刚立的课当然要做；
    /// 追加是在修一次数据不全的定格，只补当时缺的那部分，
    /// **不把定格之后才发生的意图变化折进去**，否则就是替他改写已经过完的半天。
    /// 代价是可预期性：同一件事在两台设备上可能给不同答案。接受它，
    /// 是因为初次定格只在该日尚无任何快照时触发，那一刻没有圆满可夺。
    ///
    /// **已知并接受的洞**：日初还活着、当天稍后在别处归档、本机只收到归档态的项，
    /// 永远补不回来——`activeItems()` 按 `isArchived == false` 过滤，它压根进不了这里。
    /// 这与初次定格的既有语义一致：十点归档、十一点才第一次打开，那天本来也不含它。
    /// 要堵得再加一个 `archivedAt` 同步字段，2026-07-30 权衡后不加。
    ///
    /// **两个 dayKey 直接比，不把 dayKey 反解成 Date。**
    /// `DayKeyCalendar.calendarDate(of:)` 的注释讲过为什么不能取零点：
    /// 夏令时切换日的零点根本不存在，构造出来是 nil 或被日历悄悄挪到前一天。
    /// 把 `activatedAt` 也换算成 dayKey 问的是同一件事，却全程不碰 Date 重建。
    ///
    /// `activatedAt` 若是 `.distantPast`（CloudKit 推来的记录缺该字段时的兜底值），
    /// 算出来的 dayKey 远小于任何真实日期，于是**一律追加**。方向是保守那一侧：
    /// 进了分母顶多显示未圆满，漏掉才是替他免单。
    ///
    /// **没有迟到项就一个字都不落盘**，否则每次 reload 都写一条。
    /// 追加的是**新的一条**快照，原有各条纹丝不动——「快照绝不回溯改写」的铁律不破；
    /// 并集交给 `merge`，幂等且可交换，两台设备各追加一条也不会出错。
    ///
    /// **本方法只补当次调用问的那一天**，不回溯扫描别的日子。
    /// 第 5 卷月历一律走只读的 `existingPlan(for:)`，翻月历不替任何一天补。
    /// 但补记页会对它问的那个历史日调本方法，所以**历史日并非永远补不了**：
    /// 用户再补记一次那天，缺的项就补上了，那天可能因此从圆满退回未圆满。
    /// 这是对的——补记页上的日子恰恰是他还能补做的日子。
    ///
    /// **判据绝不可套到初次定格上。** 初次定格照收全部在册定课，哪怕它们是今天才立的：
    /// 新用户补录过去三十天，那些课全是今天立的，一滤就是三十条空快照，
    /// 每天记着几百声却显示「无课」——正是本方法要治的病，反被治法造出来。
    /// 守卫见 `初次定格仍旧收下全部在册定课`。
    private func appendLateArrivals(
        to existing: DayPlan,
        dayKey: Int,
        activeItems: [PracticeItem],
        dayStartHour: Int,
        timeZone: TimeZone
    ) throws -> DayPlan {
        let known = Set(existing.requiredItemIDs)

        // ⛔ **那天的快照全是空的时候，`activatedAt` 判据一律不问。**
        //
        // 新用户的必然路径：装好 App 一打开，今日页立刻调 `plan`，那天还没快照，
        // 于是「初次定格，收下全部在册定课」——而他此刻一门课都没有，落下一条空快照。
        // 接着他点「立一门定课」，回今日页时那天**已经有**快照了，走到这里，
        // 今天立的课被 `activeSince < dayKey` 挡在外面，今日页仍旧是空态。
        // **计数器和计时器的入口只在今日页的功课行上，行不出现，他今天就记不了。**
        //
        // 2026-07-31 在模拟器里手点出来的，当时 361 条测试全绿：
        // 空快照 15:52:35 定格，第一门课 15:57:18 立，差 4 分 43 秒。
        //
        // 为什么只放宽这一处：空快照说明定格那一刻他一门课都没有，
        // **那天没有任何圆满可言，重新收下全部在册定课不从任何人手里拿走东西**。
        // 这与上面 `plan` 的初次定格分支问的是同一句话（「此刻他想做哪些课」），
        // 答案自然也该一样。已经有课的那天照旧挡住——那才是「替他改写已经过完的半天」。
        let 那天还是空的 = known.isEmpty

        let late = activeItems.filter { item in
            guard !item.isArchived, !known.contains(item.id) else { return false }
            if 那天还是空的 { return true }
            let activeSince = DayKey.make(
                from: item.activatedAt,
                tzOffsetMinutes: DayKey.currentOffsetMinutes(at: item.activatedAt, timeZone: timeZone),
                dayStartHour: dayStartHour
            )
            return activeSince < dayKey
        }
        guard !late.isEmpty else { return existing }

        var goals: [String: Int] = [:]
        for item in late {
            if let goal = item.dailyGoal, goal > 0 {
                goals[item.id.uuidString] = goal
            }
        }
        context.insert(
            DaySnapshot(dayKey: dayKey, requiredItemIDs: late.map(\.id), goals: goals)
        )
        try context.saveOrRollback()

        // 追加这条必须和原有各条一起重过 `merge`：目标的取值规则是
        // 「含该项的最早一条快照」，在这里自己拼会绕过它。
        return try existingPlan(for: dayKey) ?? existing
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
