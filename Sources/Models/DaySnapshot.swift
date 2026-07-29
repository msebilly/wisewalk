import Foundation
import SwiftData

/// 某一天「应该做哪些功课、各自目标多少」的定格快照。
///
/// 圆满判定**一律读快照，永不按当前设置实时重算**。
/// 用户今天把念佛目标从 1000 改成 3000，上个月那些标着「圆满」的日子
/// 不能因此变回「未完成」——那等于告诉他过去三十天白做了。
///
/// 注意此处**没有** `@Attribute(.unique)`：CloudKit 不支持唯一约束。
/// 同一 dayKey 出现多条快照的去重责任在 `DayLedger.snapshot(for:activeItems:)`。
@Model
final class DaySnapshot {
    var id: UUID = UUID()
    var dayKey: Int = 0

    /// 当日应做的定课项 id
    var requiredItemIDs: [UUID] = []

    /// key 为 `PracticeItem.id.uuidString`，value 为当日目标（计时类为秒）。
    /// **未设目标的项不出现在此字典中**，与 `dailyGoal == nil` 对应。
    var goals: [String: Int] = [:]

    var createdAt: Date = Date.distantPast

    init(
        id: UUID = UUID(),
        dayKey: Int,
        requiredItemIDs: [UUID],
        goals: [String: Int],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.dayKey = dayKey
        self.requiredItemIDs = requiredItemIDs
        self.goals = goals
        self.createdAt = createdAt
    }
}
