import Testing
import SwiftData
import Foundation
@testable import WiseWalk

/// 第 3 卷把账本库从「只留本机」拨到「走 iCloud」。
///
/// ⛔ **这个文件里没有一条测试能证明「同步真的在同步」。** 实测过：
/// 缺 `com.apple.developer.icloud-container-identifiers` entitlement 时，
/// `cloudKitDatabase: .automatic` 是**彻底的空操作**——容器照样建得起、不抛错，
/// 库文件里连一张 CloudKit 特征表都不会多（探针逐字节比对过前后的 store 文件）。
/// 而本机没有付费开发者账号，`CODE_SIGNING_ALLOWED` 也是 `NO`。
///
/// 也就是说，「拨这个开关会不会动到用户已有的功课」**在这台机器上答不了**，
/// 它进了真机验证清单。下面三条守的是别的东西。
@MainActor
@Test func 账本拨到iCloud时草稿库仍然不许出这台设备() throws {
    // 草稿同步出去 = 同一笔功课在两台设备上各被恢复一次（`SessionDraft` 的长注释）。
    // 拨账本这个开关时最容易顺手把两条 configuration 一起改了，所以这里钉死。
    let base = URL.temporaryDirectory.appending(path: "wisewalk-\(UUID().uuidString)",
                                                directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: base) }
    let container = try ModelContainerFactory.onDisk(baseDirectory: base, ledgerSync: .iCloud)

    let 草稿 = try #require(container.configurations.first { $0.name == "localOnly" })
    let 账本 = try #require(container.configurations.first { $0.name == "synced" })
    // `CloudKitDatabase` 既不 `Equatable` 也没有公开的判据，只能读它的描述。
    // 丑，但这是唯一拿得到的事实。
    let 草稿设置 = String(describing: 草稿.cloudKitDatabase)
    let 账本设置 = String(describing: 账本.cloudKitDatabase)
    #expect(草稿设置.contains("_none: true"), "草稿库被拨去同步了：\(草稿设置)")
    #expect(账本设置.contains("_automatic: true"), "账本没拨到 iCloud：\(账本设置)")
}

@MainActor
@Test func 只留本机时两条都不同步() throws {
    let base = URL.temporaryDirectory.appending(path: "wisewalk-\(UUID().uuidString)",
                                                directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: base) }
    let container = try ModelContainerFactory.onDisk(baseDirectory: base,
                                                     ledgerSync: .thisDeviceOnly)
    for cfg in container.configurations {
        let 设置 = String(describing: cfg.cloudKitDatabase)
        #expect(设置.contains("_none: true"), "\(cfg.name) 在「只留本机」下仍然开着同步：\(设置)")
    }
}

@MainActor
@Test func 内存测试容器两条configuration都不同步() throws {
    let container = try ModelContainerFactory.inMemory()

    for cfg in container.configurations {
        let 设置 = String(describing: cfg.cloudKitDatabase)
        #expect(设置.contains("_none: true"), "\(cfg.name) 在内存测试里启用了 CloudKit：\(设置)")
    }
}

/// 换开关不能把已经落盘的功课弄丢。
///
/// ⚠️ **这条证不了 CloudKit 的迁移安全**（理由见文件头）。它证的是更窄的一件事：
/// 换了 `onDisk` 的参数之后，同一个 store 仍然打得开、内容原样。
/// 真正的迁移安全要等真机 + 付费账号。
@MainActor
@Test func 换过同步开关之后同一个库仍然打得开且内容原样() throws {
    let base = URL.temporaryDirectory.appending(path: "wisewalk-\(UUID().uuidString)",
                                                directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: base) }
    let sessionID = UUID()

    try {
        let ctx = ModelContext(try ModelContainerFactory.onDisk(baseDirectory: base,
                                                                ledgerSync: .thisDeviceOnly))
        let item = PracticeItem(name: "念佛", measureType: .count, unit: "声")
        ctx.insert(item)
        ctx.insert(PracticeSession(id: sessionID, item: item, dayKey: 20260803,
                                   tzOffsetMinutes: 480, amount: 1080,
                                   startedAt: Date(), source: .counter,
                                   deviceName: "iPhone·TUTB"))
        try ctx.save()
    }()

    let ctx = ModelContext(try ModelContainerFactory.onDisk(baseDirectory: base,
                                                            ledgerSync: .iCloud))
    let sessions = try ctx.fetch(FetchDescriptor<PracticeSession>())
    #expect(sessions.count == 1, "换过开关后流水没了")
    #expect(sessions.first?.id == sessionID, "换过开关后流水换了身份")
    #expect(sessions.first?.amount == 1080, "换过开关后数目变了")
    #expect(sessions.first?.item?.name == "念佛", "换过开关后流水认不得它那门功课了")
}
