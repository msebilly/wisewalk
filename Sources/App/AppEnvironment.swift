import Foundation
import SwiftData
import Observation

/// 一次性装配全部仓储，让整棵视图树共用同一个 `ModelContext`。
///
/// 共用是必须的：SwiftData 的每个 `ModelContext` 各有各的待写缓冲，
/// 不共用的话，定课管理页新建的功课在今日页查不到。
///
/// **构造函数不做任何数据修复**。启动清账（`reconcilePendingDrafts`）
/// 由 `RootView` 在明确的时机调用——藏在构造函数里会让
/// 「什么时候动了用户数据」变得说不清，而这个 App 唯一不能出错的就是这件事。
@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let ledger: DayLedger
    @ObservationIgnored let items: PracticeItemStore
    @ObservationIgnored let drafts: DraftStore
    let settings: AppSettings
    /// 账本路径与 iCloud 账户状态。它会随账户变更刷新，但不声称同步已经完成。
    let syncStatus: LedgerSyncStatusMonitor

    init(container: ModelContainer,
         defaults: UserDefaults = .standard,
         syncStatus: LedgerSyncStatusMonitor? = nil) throws {
        self.container = container
        self.syncStatus = syncStatus ?? LedgerSyncStatusMonitor(
            status: .localOnly(reason: nil)
        )
        let ctx = ModelContext(container)
        self.context = ctx
        let ledger = DayLedger(context: ctx, deviceName: DeviceIdentity.displayName(defaults: defaults))
        self.ledger = ledger
        self.items = PracticeItemStore(context: ctx)
        self.drafts = DraftStore(context: ctx, ledger: ledger)
        self.settings = AppSettings(defaults: defaults)
    }
}
