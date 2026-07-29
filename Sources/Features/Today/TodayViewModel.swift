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

    /// §6.8 三态之一：应做集合为空叫**无课**，不计入分母，也不中断。
    /// 用户什么都没安排的日子不该被记一笔失败。
    var isRestDay: Bool { rows.isEmpty }

    /// 应做的都达标了。无课日**不算**圆满——那是另一种状态。
    var isFulfilled: Bool { !rows.isEmpty && rows.allSatisfy { $0.state == .fulfilled } }

    private let ledger: DayLedger
    private let items: PracticeItemStore

    init(ledger: DayLedger, items: PracticeItemStore) {
        self.ledger = ledger
        self.items = items
    }

    /// 重新载入今日清单。
    ///
    /// 这里调的是**会落库**的 `plan(for:activeItems:)` 而不是只读的 `existingPlan(for:)`，
    /// 因为「用户打开今日页」正是 §4.2 所谓「真正打开某天」——该定格快照的时刻。
    /// 它在该日已有快照时不会再写，所以反复 reload 是安全的。
    /// **第 5 卷的月历必须改用 `existingPlan(for:)`**，否则往回翻三个月就是伪造九十天历史。
    func reload(
        now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current
    ) throws {
        let key = DayKey.today(dayStartHour: dayStartHour, now: now, timeZone: timeZone)
        let active = try items.activeItems()
        let plan = try ledger.plan(for: key, activeItems: active)
        dayKey = key

        // 快照里可能有「登记时还活跃、现在已归档」的项。它们仍要显示：
        // 圆满判定一律读快照，藏起来会让今日页与月历口径打架（详见本文件顶上的取舍说明）。
        var lookup: [UUID: PracticeItem] = [:]
        for item in active { lookup[item.id] = item }
        for id in plan.requiredItemIDs where lookup[id] == nil {
            if let archived = try items.item(id: id) { lookup[id] = archived }
        }

        var built: [TodayRow] = []
        for id in plan.requiredItemIDs {
            guard let item = lookup[id] else { continue }
            built.append(TodayRow(
                itemID: id,
                name: item.name,
                unit: item.unit,
                iconName: item.iconName,
                colorHex: item.colorHex,
                measureType: item.measureType,
                goal: plan.goals[id.uuidString],
                total: try ledger.total(on: key, itemID: id),
                state: try ledger.fulfillment(of: id, plan: plan),
                isArchived: item.isArchived
            ))
        }

        // `plan.requiredItemIDs` 按 uuidString 排序（为了跨设备逐位一致），
        // 但界面要按用户自己拖的顺序。已归档的一律沉到最后。
        var rank: [UUID: Int] = [:]
        for (index, item) in active.enumerated() { rank[item.id] = index }
        rows = built.sorted {
            if $0.isArchived != $1.isArchived { return !$0.isArchived }
            return (rank[$0.itemID] ?? .max) < (rank[$1.itemID] ?? .max)
        }
    }
}
