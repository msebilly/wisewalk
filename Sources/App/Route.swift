import Foundation

/// 导航目的地。`NavigationStack` 的 path 要求 `Hashable`。
enum Route: Hashable {
    case counter(UUID)
    case timer(UUID)
    case manualEntry
    case itemList
    case itemEditor(UUID?)

    /// 某种量法该去哪里记。
    /// 勾选类返回 `nil`——就地打勾，为一个勾专门开一页是自找麻烦。
    static func forRecording(measureType: MeasureType, itemID: UUID) -> Route? {
        switch measureType {
        case .count: .counter(itemID)
        case .duration: .timer(itemID)
        case .check: nil
        }
    }
}
