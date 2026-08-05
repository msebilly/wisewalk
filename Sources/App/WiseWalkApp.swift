import SwiftUI
import SwiftData

@main
struct WiseWalkApp: App {
    @State private var env: AppEnvironment

    init() {
        do {
            // ⛔ 这里从前是 `try onDisk()` —— 而 `onDisk` 从前永远只留本机、
            // 几乎不可能失败，所以下面那句 `fatalError` 一直没显出獠牙。
            // 拨到 iCloud 之后失败的门路一下子多了起来（容器 ID 对不上、
            // schema 违反 CloudKit 约束、iCloud 被 MDM 关掉…），
            // 而那条路的尽头是**App 根本起不来**。
            // `openLedger` 会退回只留本机并带回降级理由，见它的长注释。
            let opened = try ModelContainerFactory.openLedger()
            let syncStatus = LedgerSyncStatusMonitor(opened: opened)
            _env = State(initialValue: try AppEnvironment(container: opened.container,
                                                          syncStatus: syncStatus))
        } catch {
            // 数据库打不开意味着用户看不到自己的功课。
            // 此处不做静默降级——降级会让人以为记录丢了，比崩溃更伤。
            //
            // 走到这里说明**连「只留本机」都开不出来**（`openLedger` 已经替
            // 「iCloud 开不出来」兜过一次底了），那才是真的没救。
            fatalError("无法打开数据库：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(env: env)
        }
    }
}
