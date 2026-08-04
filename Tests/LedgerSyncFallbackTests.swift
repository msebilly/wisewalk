import Testing
import SwiftData
import Foundation
@testable import WiseWalk

/// 拨到 iCloud 之后，「账本库打不开」这条路的尽头从前是 `fatalError`。
///
/// `onDisk` 从前永远只留本机、几乎不可能失败，所以那句 `fatalError` 一直没显出獠牙。
/// 拨过去之后失败的门路一下子多了起来，而那条路的尽头是**App 根本起不来**——
/// 用户连自己念了多少都看不到。下面这几条守的是那道退路。
struct 账本降级Tests {

    /// 内存容器，只为让注入的闭包有东西可返回。
    @MainActor
    private func 随便一个容器() throws -> ModelContainer {
        try ModelContainerFactory.inMemory()
    }

    @MainActor
    @Test func 账本按要求开得出来时不许降级() throws {
        var 要过的路: [LedgerSync] = []
        let opened = try ModelContainerFactory.openLedger(requested: .iCloud) { sync in
            要过的路.append(sync)
            return try self.随便一个容器()
        }
        #expect(opened.sync == .iCloud, "开得出来却降级了")
        #expect(opened.fallbackReason == nil, "没降级却报了降级理由")
        #expect(要过的路 == [.iCloud], "开一次就够，却走了 \(要过的路)")
    }

    @MainActor
    @Test func 生产入口默认要求走iCloud() throws {
        var 要过的路: [LedgerSync] = []
        _ = try ModelContainerFactory.openLedger { sync in
            要过的路.append(sync)
            return try self.随便一个容器()
        }

        #expect(要过的路 == [.iCloud], "生产默认没有请求 iCloud：\(要过的路)")
    }

    @MainActor
    @Test func iCloud开不出来就退回只留本机而不是崩掉() throws {
        struct 开不出来: Error {}
        var 要过的路: [LedgerSync] = []
        let opened = try ModelContainerFactory.openLedger(requested: .iCloud) { sync in
            要过的路.append(sync)
            if sync == .iCloud { throw 开不出来() }
            return try self.随便一个容器()
        }
        #expect(opened.sync == .thisDeviceOnly, "没退回本机")
        // 退路必须真的是「只留本机」那条，不能拿别的参数凑数——
        // 退回去的那次要是也带着 iCloud，等于原地打转。
        #expect(要过的路 == [.iCloud, .thisDeviceOnly], "退路走错了：\(要过的路)")
    }

    /// ⛔ 降级本身不可怕，**闷声降级才可怕**。
    /// 这个理由要一路交到界面上（`LedgerSyncStatus.barText`）。
    @MainActor
    @Test func 降级的理由不许丢() throws {
        struct 容器ID对不上: Error {}
        let opened = try ModelContainerFactory.openLedger(requested: .iCloud) { sync in
            if sync == .iCloud { throw 容器ID对不上() }
            return try self.随便一个容器()
        }
        let 理由 = try #require(opened.fallbackReason, "降级了却没留下任何理由")
        #expect(理由.contains("容器ID对不上"), "理由里没有真正的错因：\(理由)")
    }

    /// 本来就只留本机的话，没有第二条路可退。
    /// 这才是 `WiseWalkApp` 那个 `fatalError` 真正该管的那种失败。
    @MainActor
    @Test func 只留本机也打不开时如实抛出去() throws {
        struct 磁盘满了: Error {}
        var 试了几次 = 0
        #expect(throws: 磁盘满了.self) {
            _ = try ModelContainerFactory.openLedger(requested: .thisDeviceOnly) { _ in
                试了几次 += 1
                throw 磁盘满了()
            }
        }
        #expect(试了几次 == 1, "没有退路可走，却反复试了 \(试了几次) 次")
    }

    /// 两条都开不出来时，抛的必须是**本机那次**的错。
    /// 用户看到的那句话说的应该是「数据库打不开」，不是「iCloud 怎么了」——
    /// 后者会让他去折腾 iCloud 设置，而那根本不是病根。
    @MainActor
    @Test func 两条路都断了时报的是本机那次的错() throws {
        struct iCloud的错: Error {}
        struct 本机的错: Error {}
        #expect(throws: 本机的错.self) {
            _ = try ModelContainerFactory.openLedger(requested: .iCloud) { sync in
                throw sync == .iCloud ? iCloud的错() as Error : 本机的错() as Error
            }
        }
    }

    @MainActor
    @Test func 降级后仍从同一落盘账本读到原记录() throws {
        struct iCloud开不了: Error {}
        let base = URL.temporaryDirectory.appending(
            path: "wisewalk-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        defer { try? FileManager.default.removeItem(at: base) }
        let sessionID = UUID()

        try {
            let ctx = ModelContext(try ModelContainerFactory.onDisk(
                baseDirectory: base,
                ledgerSync: .thisDeviceOnly
            ))
            let item = PracticeItem(name: "念佛", measureType: .count, unit: "声")
            ctx.insert(item)
            ctx.insert(PracticeSession(
                id: sessionID,
                item: item,
                dayKey: 20260803,
                tzOffsetMinutes: 480,
                amount: 108,
                startedAt: Date(),
                source: .counter,
                deviceName: "T"
            ))
            try ctx.save()
        }()

        let opened = try ModelContainerFactory.openLedger(
            baseDirectory: base,
            requested: .iCloud
        ) { sync in
            if sync == .iCloud { throw iCloud开不了() }
            return try ModelContainerFactory.onDisk(baseDirectory: base, ledgerSync: sync)
        }
        let ctx = ModelContext(opened.container)
        let sessions = try ctx.fetch(FetchDescriptor<PracticeSession>())

        #expect(opened.sync == .thisDeviceOnly)
        #expect(sessions.map(\.id) == [sessionID], "降级换了库或改了原记录")
        #expect(sessions.first?.amount == 108, "降级改动了原记录")
    }

    /// ⛔ Swift 的默认值表达式引用不到同一个签名里的别的参数。
    /// `open` 那个参数一旦写成带默认闭包的形式，`baseDirectory` 就会被默默吞掉，
    /// 测试指着临时目录、实现却往真的 Application Support 里写。
    @MainActor
    @Test func 生产那条路真的用上了传进来的目录() throws {
        let base = URL.temporaryDirectory.appending(path: "wisewalk-\(UUID().uuidString)",
                                                    directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base) }

        _ = try ModelContainerFactory.openLedger(baseDirectory: base, requested: .thisDeviceOnly)

        let 账本 = base.appendingPathComponent("WiseWalk.store")
        #expect(FileManager.default.fileExists(atPath: 账本.path),
                "账本没落在传进来的目录里，`baseDirectory` 被吞了")
    }
}

/// 同步状态只报我们确知的事，不报**货到没到**。
struct 同步状态Tests {

    @MainActor
    @Test func 走iCloud且没降级时先进入检查中() throws {
        let c = try ModelContainerFactory.inMemory()
        let 状态 = LedgerSyncStatus(LedgerOpen(container: c, sync: .iCloud, fallbackReason: nil))
        #expect(状态 == .checking)
    }

    @MainActor
    @Test func 降级之后算只在本机并且带着理由() throws {
        let c = try ModelContainerFactory.inMemory()
        let 降 = LedgerSyncStatus(LedgerOpen(container: c, sync: .thisDeviceOnly,
                                             fallbackReason: "容器 ID 对不上"))
        #expect(降 == .localOnly(reason: "容器 ID 对不上"))
    }

    @MainActor
    @Test func 本来就没要求同步不算出事() throws {
        let c = try ModelContainerFactory.inMemory()
        let 本机 = LedgerSyncStatus(LedgerOpen(container: c, sync: .thisDeviceOnly,
                                              fallbackReason: nil))
        #expect(本机 == .localOnly(reason: nil))
        #expect(本机.barText == "记录目前只在这台设备上 · 未启用 iCloud")
    }

    @Test func 状态栏每一档都只说对应的事实() {
        let 每一档: [(LedgerSyncStatus, String)] = [
            (.checking, "正在检查 iCloud 可用性"),
            (.available, "iCloud 可用 · 记录将备份到 iCloud"),
            (.noAccount, "记录目前只在这台设备上 · 未登录 iCloud"),
            (.restricted, "记录目前只在这台设备上 · iCloud 账户受限"),
            (.couldNotDetermine, "记录目前只在这台设备上 · 无法确定 iCloud 账户状态"),
            (.temporarilyUnavailable, "记录目前只在这台设备上 · iCloud 暂时不可用"),
            (.accountLookupFailed(reason: "无法连接账户服务"),
             "记录目前只在这台设备上 · 无法查询 iCloud 账户"),
            (.localOnly(reason: "容器 ID 对不上"),
             "记录目前只在这台设备上 · iCloud 数据库未能打开"),
            (.localOnly(reason: nil),
             "记录目前只在这台设备上 · 未启用 iCloud")
        ]

        for (状态, 事实) in 每一档 {
            #expect(状态.barText == 事实, "\(状态) 说成了：\(状态.barText)")
        }
    }

    /// ⛔⛔ **绝不许承诺「已备份 / 已同步」。**
    ///
    /// SwiftData 在 iOS 17 没暴露 `eventChangedNotification`，
    /// 我们拿不到任何一次同步的成败，也数不出待上传条数。
    /// `docs/design-spec.md` §5.2 原本要求常驻「已备份 · 刚刚」——**那句说不出口**，
    /// 而且是方向最坏的一句谎：用户读完就放心了，换手机时才发现什么都没有。
    ///
    /// 这条钉的是一整族词，不是某一句文案：谁哪天想「顺手把状态做得完整点」，
    /// 都会在这里被拦下来。
    @Test func 任何一档都不许出现无法证实的词族() {
        let 不许出现 = ["已备份", "已同步", "同步完成", "备份完成", "刚刚",
                     "待上传", "上次同步", "已上传", "安全", "已保存到 iCloud",
                     "同步已开启", "备份已开启"]
        let 每一档: [LedgerSyncStatus] = [
            .checking, .available, .noAccount, .restricted, .couldNotDetermine,
            .temporarilyUnavailable, .accountLookupFailed(reason: "任意错因"),
            .localOnly(reason: nil), .localOnly(reason: "任意错因")
        ]
        for 状态 in 每一档 {
            let 话 = 状态.barText
            for 词 in 不许出现 {
                #expect(!话.contains(词),
                        "\(状态) 说了「\(词)」——我们根本不知道同步到哪一步了：\(话)")
            }
        }
    }
}
