import Foundation

/// 账本同步这件事上，**我们真正知道的那点事**。
///
/// ⛔ **这里没有「已备份」「已同步」「上次同步于…」，是故意的。**
///
/// `docs/design-spec.md` §5.2 原本要求今日页底部常驻
/// 「已备份 · 刚刚」/「有 2 条待上传 · 等待网络」/「备份出错 · 查看」。
/// **那三句我们一句都说不出口**：SwiftData 在 iOS 17 没有暴露
/// `NSPersistentCloudKitContainer.eventChangedNotification`，
/// 我们拿不到任何一次同步的开始、结束、成败，也数不出待上传条数。
/// 硬要显示就只能靠猜，而猜出来的每一句都是编的。
///
/// 「已备份 · 刚刚」还是**方向最坏的那一句**：用户读完就放心了，
/// 换手机时才发现什么都没有。这个 App 的立身之本是「一声都不能丢」，
/// 而**说不知道的事，比不说更坏**——闭口至少不会让人误以为安全。
///
/// 所以这里只报**路通不通**，不报**货到没到**。
enum LedgerSyncStatus: Equatable {
    /// 账本按要求走 iCloud，路开出来了。
    ///
    /// ⛔ **这不等于「已经同步好了」。** 容器开成功之后 CloudKit 还可能
    /// 因为没登录 iCloud、没网、配额满而一条都传不上去，而我们看不见。
    case pathOpen

    /// 记录只在这台设备上。
    /// - Parameter reason: 降级的原因；`nil` 表示本来就没要求同步（不是出错）。
    case localOnly(reason: String?)

    init(_ opened: LedgerOpen) {
        switch (opened.sync, opened.fallbackReason) {
        case (.iCloud, nil): self = .pathOpen
        case (_, let why): self = .localOnly(reason: why)
        }
    }

    /// 要不要在今日页说话，说什么。**`nil` = 一个字都不说。**
    ///
    /// 「可用时不打扰」（§5.1）：路通着就闭嘴。真正非说不可的只有一种——
    /// **我们承诺过记录在 iCloud 里，而它此刻不在**。§5.3 说得明白，
    /// 「只有一台设备、没登 iCloud」恰恰是最危险的用户。
    ///
    /// 只陈述事实，不出主意（同 `RecoveryCoordinator.alreadyOnBooks`）：
    /// 用户是该去登 iCloud、还是该导出备份、还是根本不在乎，我们不知道。
    var notice: String? {
        switch self {
        case .pathOpen: nil
        case .localOnly(nil): nil
        case .localOnly(.some): "记录目前只存在这台设备上，没有传到 iCloud。"
        }
    }
}
