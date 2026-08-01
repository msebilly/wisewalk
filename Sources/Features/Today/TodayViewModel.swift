import Foundation
import SwiftData
import Observation

/// 今日页上的一行。**值类型**——视图不直接碰 SwiftData 对象，
/// 这样视图逻辑才能在没有容器的情况下被测试，也不会因为对象被同步改动而在渲染中途变形。
struct TodayRow: Identifiable, Equatable, Sendable {
    let itemID: UUID
    let name: String
    /// 量词。计时类与勾选类为空串。
    let unit: String
    let iconName: String
    let colorHex: String
    let measureType: MeasureType
    /// 当日目标。**nil 表示不设目标**，此时「做了就算圆满」。
    let goal: Int?
    /// 当日显示总量（负数已 clamp）。计时类为秒。
    let total: Int
    /// 当日「做了几回」。计时类是坐数：正数、非 `.adjustment` 的流水条数，撤销与修正不算。
    let roundCount: Int
    let state: FulfillmentState
    /// 当日快照登记过它，但用户之后把它归档了。只会在归档当天出现。
    let isArchived: Bool

    var id: UUID { itemID }

    /// 进度 0…1。
    /// 不设目标时「做了就是满的」——与 `LedgerMath.isFulfilled` 同一条口径。
    /// 超额完成封顶在 1：进度条冲出圆环没有意义，而 `total` 会照实显示。
    var progress: Double {
        guard let goal, goal > 0 else { return total > 0 ? 1 : 0 }
        return min(1, Double(total) / Double(goal))
    }
}

/// 今日页的状态机。**所有分支逻辑都在这里**，视图只管画。
@MainActor
@Observable
final class TodayViewModel {
    private(set) var dayKey: Int = 0
    private(set) var rows: [TodayRow] = []

    /// 今天新立、但今天还用不了的定课名字。
    ///
    /// 今天的清单在他今天头一回打开 App 时就定格了，之后立的课不追加进来——
    /// 这是 `appendLateArrivals` 明确不许修平的不对称（守卫测试
    /// `已经有课的那天新立的课仍旧不算今天` 钉着它）：上午已经显示出来的圆满
    /// 不能因为下午加了一门课就退回未圆满，那是替他改写已经过完的半天。
    ///
    /// **设计对，但屏幕上从前一个字都没说。** 他 17:02 立了打坐，回今日页看不见，
    /// 分不清这是「明天才算」还是「刚才没存上」——后一种解释会让他再立一遍，
    /// 于是有了两门重名的课。这条属性就是拿来把话说出来的。
    ///
    /// ⚠️ **只装活跃的课。** 归档的课不在今天清单里是因为归档了，
    /// 说它「从明天起算」是假话——它明天也不会出现。
    private(set) var startingTomorrow: [String] = []

    /// 快照登记了、本机却找不到对应定课的应做项。
    ///
    /// `DaySnapshot.requiredItemIDs` 是裸 `[UUID]` 不是关系，而 CloudKit 把
    /// `DaySnapshot` 与 `PracticeItem` 当两种独立记录同步，**不保证到达顺序、
    /// 也没有引用完整性**。换新机或重装后首次启动，完全可能快照先到、定课未到。
    ///
    /// **这些 id 必须留在三态判定里。** 把它们静默跳过、再拿 `rows` 推三态的话：
    /// 少一项而其余都达标 → 报「今日圆满」；全丢 → 报「今日无课」（不计入分母、
    /// 不中断连续天数）。账本一声没丢——流水与快照都原封不动，同步补齐后自愈——
    /// 但**报告层**替用户宣布了他没做到的事，这是「一声都不能多」的另一种犯法。
    /// 宁可降级成「未圆满」：错也要错在保守那一侧。
    private(set) var unresolvedItemIDs: [UUID] = []

    /// 今日应做的项数，**含尚未同步到本机的**。
    var requiredCount: Int { rows.count + unresolvedItemIDs.count }

    /// §6.8 三态之一：**应做集合**为空叫无课，不计入分母，也不中断。
    /// 用户什么都没安排的日子不该被记一笔失败。
    ///
    /// 判据是应做集合而不是 `rows`——§6.8 的原话就是「应做集合为空」，
    /// 而 `rows` 只是其中**画得出来**的那部分。同步窗口内两者会分家。
    var isRestDay: Bool { requiredCount == 0 }

    /// 应做的都达标了。无课日**不算**圆满——那是另一种状态。
    /// 有项目还没同步到本机时一律不算圆满：它们做没做，本机根本不知道。
    var isFulfilled: Bool {
        requiredCount > 0 && unresolvedItemIDs.isEmpty
            && rows.allSatisfy { $0.state == .fulfilled }
    }

    private let ledger: DayLedger
    private let items: PracticeItemStore

    init(ledger: DayLedger, items: PracticeItemStore) {
        self.ledger = ledger
        self.items = items
    }

    /// 重新载入今日清单。
    ///
    /// 这里调的是**会落库**的 `plan(for:activeItems:)` 而不是只读的 `existingPlan(for:)`，
    /// 因为「用户真正打开或记录某天」才准定格快照——见本卷计划的总纪律与
    /// `DayLedger.plan(for:activeItems:)` 自己的文档注释。
    /// （design-spec §4.2 只写到「每天首次产生记录时冻结」，「打开今日页也算」是本卷的补充口径；
    /// Task 14 会在 `.task` 与 `scenePhase == .active` 时调本方法。
    /// 「进前台」算不算「真正打开」曾经悬而未决，Task 13.5 之后**不必再纠结**：
    /// 提前定格出的残缺快照会被 `DayLedger` 的追加逻辑补回来，误触发不再是永久损失。）
    /// 它在该日**已有快照且没有迟到项**时才不写，所以反复 reload 是安全的。
    /// **第 5 卷的月历必须改用 `existingPlan(for:)`**，否则往回翻三个月就是伪造九十天历史。
    func reload(
        now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current
    ) throws {
        let key = DayKey.today(dayStartHour: dayStartHour, now: now, timeZone: timeZone)
        let active = try items.activeItems()
        let plan = try ledger.plan(
            for: key,
            activeItems: active,
            dayStartHour: dayStartHour,
            timeZone: timeZone
        )

        // 快照里可能有「登记时还活跃、现在已归档」的项。它们仍要显示：
        // 圆满判定一律读快照，藏起来会让今日页与月历口径打架（详见本文件顶上的取舍说明）。
        var lookup: [UUID: PracticeItem] = [:]
        for item in active { lookup[item.id] = item }
        for id in plan.requiredItemIDs where lookup[id] == nil {
            if let archived = try items.item(id: id) { lookup[id] = archived }
        }

        var built: [TodayRow] = []
        var unresolved: [UUID] = []
        for id in plan.requiredItemIDs {
            guard let item = lookup[id] else {
                // 快照登记了它、本机却没有——同步半到。**不许静默跳过**，
                // 跳过就等于把它从三态判定的分母里抹掉（详见 `unresolvedItemIDs`）。
                unresolved.append(id)
                continue
            }
            built.append(TodayRow(
                itemID: id,
                name: item.name,
                unit: item.unit,
                iconName: item.iconName,
                colorHex: item.colorHex,
                measureType: item.measureType,
                goal: plan.goals[id.uuidString],
                total: try ledger.total(on: key, itemID: id),
                roundCount: try ledger.roundCount(on: key, itemID: id),
                state: try ledger.fulfillment(of: id, plan: plan),
                isArchived: item.isArchived
            ))
        }

        // `plan.requiredItemIDs` 按 uuidString 排序（为了跨设备逐位一致），
        // 但界面要按用户自己拖的顺序。已归档的一律沉到最后。
        //
        // 名次取自 `active.enumerated()` 的下标而**不是** `item.sortOrder`：
        // `PracticeItemStore.reorder` 收的是活跃子集，重排后 sortOrder 会与归档项撞号
        // （那里的文档注释写明了这一点），用枚举下标正好绕开。别「优化」成读 sortOrder。
        var rank: [UUID: Int] = [:]
        for (index, item) in active.enumerated() { rank[item.id] = index }
        let sorted = built.sorted {
            if $0.isArchived != $1.isArchived { return !$0.isArchived }
            return (rank[$0.itemID] ?? .max) < (rank[$1.itemID] ?? .max)
        }

        // 活跃、却不在今天清单里的课 = 今天定格之后才立的。
        // 取自 `active` 所以归档的天然不在其中；顺序跟着用户自己拖的顺序走。
        let 今天要做的 = Set(plan.requiredItemIDs)
        let 明天起算 = active.filter { !今天要做的.contains($0.id) }.map(\.name)

        // 三个状态**一起换**。上面每一步都会 throw（全是 fetch），
        // 中途换掉 `dayKey` 的话，抛错时视图会显示今天的日期配昨天的清单——
        // 而调用方（Task 14）只弹 alert、不回滚。
        // 更要命的是 Task 14 的 `toggleCheckbox` 拿陈旧行的 `total == 0`
        // 配新的 `onDay: dayKey` 去决定记账还是撤销，会多记一笔。
        dayKey = key
        rows = sorted
        unresolvedItemIDs = unresolved
        startingTomorrow = 明天起算
    }

    /// 勾选类的打勾／取消。
    ///
    /// 取消**不删记录**——追加一笔等额负数（走 `DayLedger.revoke`，它以
    /// `revoke:<原记录 id>` 为幂等键）。append-only 是这个 App 的地基：
    /// 真删记录会让同步冲突时无从对账，而对账不了就等于丢功课。
    ///
    /// 只对勾选类且未归档的项生效。念佛点一下记 1 声是计数器的事，
    /// 别让今日页也能记数；归档当天该项仍显示（口径统一）但不该还能往里记。
    func toggleCheckbox(
        itemID: UUID,
        at now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current
    ) throws {
        guard let row = rows.first(where: { $0.itemID == itemID }),
              row.measureType == .check,
              !row.isArchived,
              let item = try items.item(id: itemID) else { return }

        if row.total > 0 {
            let positives = try ledger.sessions(on: dayKey, itemID: itemID)
                .filter { $0.amount > 0 }
                .sorted { ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString) }
            for s in positives {
                try ledger.revoke(s, at: now, timeZone: timeZone)
            }
        } else {
            try ledger.record(
                item: item, amount: 1, source: .manual,
                startedAt: now, endedAt: now, at: now,
                dayStartHour: dayStartHour, timeZone: timeZone,
                onDay: dayKey
            )
        }
        try reload(now: now, dayStartHour: dayStartHour, timeZone: timeZone)
    }
}
