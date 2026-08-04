import Foundation
import CloudKit
import Observation

private final class NotificationObserverToken: @unchecked Sendable {
    private let notificationCenter: NotificationCenter
    private let token: NSObjectProtocol

    init(notificationCenter: NotificationCenter, token: NSObjectProtocol) {
        self.notificationCenter = notificationCenter
        self.token = token
    }

    deinit {
        notificationCenter.removeObserver(token)
    }
}

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
/// 所以这里只报**路径与账户是否可用**，不报**货到没到**。
enum LedgerSyncStatus: Equatable, Sendable {
    case checking
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
    case accountLookupFailed(reason: String)

    /// 记录只在这台设备上。
    /// - Parameter reason: 降级的原因；`nil` 表示本来就没要求同步（不是出错）。
    case localOnly(reason: String?)

    init(_ opened: LedgerOpen) {
        switch (opened.sync, opened.fallbackReason) {
        case (.iCloud, nil): self = .checking
        case (_, let why): self = .localOnly(reason: why)
        }
    }

    /// 底部那条常驻状态说什么（§6.1 要求它**常驻**，所以永远有话说）。
    ///
    /// 只陈述事实，不出主意（同 `RecoveryCoordinator.alreadyOnBooks`）：
    /// 用户是该去登 iCloud、还是该导出备份、还是根本不在乎，我们不知道。
    var barText: String {
        switch self {
        case .checking:
            "正在检查 iCloud 可用性"
        case .available:
            "iCloud 可用 · 记录将备份到 iCloud"
        case .noAccount:
            "记录目前只在这台设备上 · 未登录 iCloud"
        case .restricted:
            "记录目前只在这台设备上 · iCloud 账户受限"
        case .couldNotDetermine:
            "记录目前只在这台设备上 · 无法确定 iCloud 账户状态"
        case .temporarilyUnavailable:
            "记录目前只在这台设备上 · iCloud 暂时不可用"
        case .accountLookupFailed:
            "记录目前只在这台设备上 · 无法查询 iCloud 账户"
        case .localOnly(.some):
            "记录目前只在这台设备上 · iCloud 数据库未能打开"
        case .localOnly(nil):
            "记录目前只在这台设备上 · 未启用 iCloud"
        }
    }
}

@MainActor
@Observable
final class LedgerSyncStatusMonitor {
    private(set) var status: LedgerSyncStatus

    @ObservationIgnored private let accountClient: CloudAccountStatusClient
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var accountChangeObserver: NotificationObserverToken?
    @ObservationIgnored private let usesICloud: Bool
    @ObservationIgnored private var refreshGeneration = 0

    init(status: LedgerSyncStatus) {
        self.status = status
        self.accountClient = CloudAccountStatusClient { .couldNotDetermine }
        self.notificationCenter = NotificationCenter()
        self.usesICloud = false
    }

    init(opened: LedgerOpen,
         accountClient: CloudAccountStatusClient = .live,
         notificationCenter: NotificationCenter = .default) {
        self.accountClient = accountClient
        self.notificationCenter = notificationCenter
        self.usesICloud = opened.sync == .iCloud && opened.fallbackReason == nil
        self.status = usesICloud ? .checking : LedgerSyncStatus(opened)

        guard usesICloud else { return }
        let token = notificationCenter.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
        accountChangeObserver = NotificationObserverToken(
            notificationCenter: notificationCenter,
            token: token
        )
    }

    func refresh() async {
        guard usesICloud else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        status = .checking
        do {
            let availability = try await accountClient.fetch()
            guard generation == refreshGeneration else { return }
            switch availability {
            case .available: status = .available
            case .noAccount: status = .noAccount
            case .restricted: status = .restricted
            case .couldNotDetermine: status = .couldNotDetermine
            case .temporarilyUnavailable: status = .temporarilyUnavailable
            }
        } catch {
            guard generation == refreshGeneration else { return }
            status = .accountLookupFailed(reason: error.localizedDescription)
        }
    }
}
