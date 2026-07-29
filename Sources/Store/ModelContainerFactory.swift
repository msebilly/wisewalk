import Foundation
import SwiftData

/// Schema 与容器的唯一装配处。
///
/// 新增实体只需改这里一处，`CloudKitConstraintTests` 会自动把新实体
/// 一并纳入 §4.6 四条约束的检查范围。
enum ModelContainerFactory {
    static let schema = Schema([
        PracticeItem.self,
        PracticeSession.self,
        DaySnapshot.self
    ])

    /// 测试用：内存容器，不落盘、不同步。
    static func inMemory() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }

    /// 生产用：本地落盘。
    /// 第 3 卷「同步」会在此处补上 `cloudKitDatabase: .automatic` 与 entitlements。
    static func onDisk() throws -> ModelContainer {
        try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        )
    }
}
