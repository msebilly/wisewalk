import SwiftUI
import SwiftData

@main
struct WiseWalkApp: App {
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainerFactory.onDisk()
        } catch {
            // 数据库打不开意味着用户看不到自己的功课。
            // 此处不做静默降级——降级会让人以为记录丢了，比崩溃更伤。
            fatalError("无法打开数据库：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
