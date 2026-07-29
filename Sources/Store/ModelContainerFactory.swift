import Foundation
import SwiftData

/// Schema 与容器的唯一装配处。
///
/// **两套 schema，不是一套**：
/// - `syncedSchema` —— 账本本体。第 3 卷会给它换上 `cloudKitDatabase: .automatic`
/// - `localSchema` —— 草稿。**永远 `.none`**，永不离开这台设备（理由见 `SessionDraft`）
///
/// 两者同处一个 `ModelContainer`，因此**一次 `context.save()` 能同时完成
/// 「写流水」与「删草稿」**，满足 §4.5 第 1 条「同一事务」。
///
/// 新增**同步**实体只需改 `syncedModels`，`CloudKitConstraintTests`
/// 会自动把它纳入 §4.6 四条约束与属性白名单的检查范围。
enum ModelContainerFactory {
    static let syncedModels: [any PersistentModel.Type] = [
        PracticeItem.self,
        PracticeSession.self,
        DaySnapshot.self
    ]

    static let localModels: [any PersistentModel.Type] = [
        SessionDraft.self
    ]

    static let syncedSchema = Schema(syncedModels)
    static let localSchema = Schema(localModels)
    private static let fullSchema = Schema(syncedModels + localModels)

    /// 测试用：内存容器，不落盘、不同步。
    static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: fullSchema,
            configurations:
                ModelConfiguration("synced", schema: syncedSchema,
                                   isStoredInMemoryOnly: true, cloudKitDatabase: .none),
                ModelConfiguration("localOnly", schema: localSchema,
                                   isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }

    /// 生产用：本地落盘，两个独立的 store 文件。
    ///
    /// 第 3 卷「同步」只需把 `synced` 那条的 `cloudKitDatabase` 改成 `.automatic`
    /// 并补上 entitlements；`localOnly` 那条**永远保持 `.none`**。
    ///
    /// 落盘路径写死而不是用默认值：两个 configuration 必须落在两个不同文件上，
    /// 靠默认命名去猜是在赌 SwiftData 的实现细节。
    static func onDisk() throws -> ModelContainer {
        let dir = URL.applicationSupportDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return try ModelContainer(
            for: fullSchema,
            configurations:
                ModelConfiguration("synced", schema: syncedSchema,
                                   url: dir.appendingPathComponent("WiseWalk.store"),
                                   cloudKitDatabase: .none),
                ModelConfiguration("localOnly", schema: localSchema,
                                   url: dir.appendingPathComponent("WiseWalkLocal.store"),
                                   cloudKitDatabase: .none)
        )
    }
}
