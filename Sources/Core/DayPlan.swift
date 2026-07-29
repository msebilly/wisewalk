import Foundation

/// 某一天的应做清单——由该日**所有** `DaySnapshot` 合并推导而来的只读视图。
///
/// 刻意是值类型而非 `DaySnapshot` 本身：合并结果是**派生量**，
/// 不该回写进任何一条源记录。源快照保持各设备当初写下的原样，
/// 每次读取重新合并，因此天然自愈，也不会因为「读一下」就惊动 CloudKit。
struct DayPlan: Equatable, Sendable {
    let dayKey: Int
    let requiredItemIDs: [UUID]
    let goals: [String: Int]
}
