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
/// 账本库走不走 iCloud。**只管账本，草稿永远不走**（理由见 `SessionDraft`）。
///
/// 这是个参数而不是编译期常量，为的是让「拨这个开关会不会动到用户已有的功课」
/// 变成一条跑得起来的测试。拨开关这件事本身没法回滚——
/// 用户的历史一旦没了就是没了，只能事前证明它不会没。
enum LedgerSync {
    /// 账本经 CloudKit 在用户自己的设备间同步。
    case iCloud
    /// 账本只留本机。第 3 卷之前的行为；测试与「用户关掉了同步」都走这条。
    case thisDeviceOnly

    var database: ModelConfiguration.CloudKitDatabase {
        switch self {
        case .iCloud: .automatic
        case .thisDeviceOnly: .none
        }
    }
}

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

    /// 把 `url` 排除出 iCloud / 本地备份。**排除目录时其内容一并排除**，
    /// 这正是草稿库要单独占一个子目录的原因——SwiftData 的一个 store
    /// 落盘其实是 `.store` / `-wal` / `-shm` 三个文件，只排除主文件是漏的。
    ///
    /// 为什么非做不可：草稿库若进了备份，就会出现「跨时间的重复记账」——
    /// 备份发生在做完功课**之前**，此刻草稿还在；做完之后草稿删了、流水写了，
    /// 但这次改动还没被备份到。用户换机一恢复，拿到的是「有旧草稿、没有那笔流水」
    /// 的状态，`DraftRecovery` 启动时把它捞出来弹「要恢复吗」，
    /// 用户点确认 → 同一笔功课记两遍。
    /// 这与草稿同步出去是同一个故障，只是把「跨设备」换成了「跨时间」。
    static func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    /// 生产用：本地落盘，两个独立的 store 文件。
    ///
    /// 第 3 卷「同步」只需把 `synced` 那条的 `cloudKitDatabase` 改成 `.automatic`
    /// 并补上 entitlements；`localOnly` 那条**永远保持 `.none`**。
    ///
    /// 落盘路径写死而不是用默认值：两个 configuration 必须落在两个不同文件上，
    /// 靠默认命名去猜是在赌 SwiftData 的实现细节。
    ///
    /// 账本库**要**进备份——那是用户的功课历史。草稿库**不**进（见 `excludeFromBackup`）。
    ///
    /// `baseDirectory` 有默认值，生产调用处不必传；开个口子是为了让测试
    /// 能指向临时目录，从而真正验证「草稿库确实落在被排除的子目录里」——
    /// 只测 `excludeFromBackup` 这个函数本身，证明不了 `onDisk` 真的调了它。
    static func onDisk(baseDirectory: URL = URL.applicationSupportDirectory,
                       ledgerSync: LedgerSync = .thisDeviceOnly) throws -> ModelContainer {
        let localDir = baseDirectory.appending(path: "LocalOnly", directoryHint: .isDirectory)
        let fm = FileManager.default
        try fm.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        try fm.createDirectory(at: localDir, withIntermediateDirectories: true)
        try excludeFromBackup(localDir)
        return try ModelContainer(
            for: fullSchema,
            configurations:
                ModelConfiguration("synced", schema: syncedSchema,
                                   url: baseDirectory.appendingPathComponent("WiseWalk.store"),
                                   cloudKitDatabase: ledgerSync.database),
                ModelConfiguration("localOnly", schema: localSchema,
                                   url: localDir.appendingPathComponent("WiseWalkLocal.store"),
                                   cloudKitDatabase: .none)
        )
    }
}
