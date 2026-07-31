import SwiftUI
import SwiftData

@main
struct WiseWalkApp: App {
    @State private var env: AppEnvironment

    init() {
        do {
            let container = try ModelContainerFactory.onDisk()
            _env = State(initialValue: try AppEnvironment(container: container))
        } catch {
            // 数据库打不开意味着用户看不到自己的功课。
            // 此处不做静默降级——降级会让人以为记录丢了，比崩溃更伤。
            fatalError("无法打开数据库：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(env: env)
        }
    }
}
