import Foundation

/// 某项定课在某一天的完成状态。
///
/// 刻意区分 `.notRequired` 与 `.fulfilled`：
/// 月历上「今天本来就不用做」和「做完了」必须是两种颜色，
/// 把二者混为一谈会让用户以为自己做了实际没做的功课。
enum FulfillmentState: Equatable, Sendable {
    /// 当日清单里没有这一项
    case notRequired
    /// 在清单里，尚未达成
    case pending
    /// 在清单里，已达成
    case fulfilled
}
