import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
@Test func 装配保留可刷新的同步状态而不是一张启动快照() async throws {
    let container = try ModelContainerFactory.inMemory()
    let monitor = LedgerSyncStatusMonitor(
        opened: LedgerOpen(container: container, sync: .iCloud, fallbackReason: nil),
        accountClient: CloudAccountStatusClient { .available },
        notificationCenter: NotificationCenter()
    )
    let env = try AppEnvironment(
        container: container,
        defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!,
        syncStatus: monitor
    )

    #expect(env.syncStatus === monitor)
    await monitor.refresh()
    #expect(env.syncStatus.status == .available)
}

@MainActor
@Test func 装配后三个仓储共用同一个上下文() throws {
    // 不共用的话，A 存的东西 B 查不到——SwiftData 的 ModelContext 各有各的待写缓冲。
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: 1000, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    let now = Date()
    try env.ledger.record(item: item, amount: 108, source: .counter,
                          startedAt: now, at: now)
    #expect(try env.ledger.total(on: DayKey.today(now: now), itemID: item.id) == 108)

    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    #expect(try env.drafts.draft(for: item.id)?.id == draft.id)

    // 上面那两句照得出 `items` 不共用（换掉 items 的 context，:17 和 :20 都会红），
    // 但**照不出 `drafts` 不共用**：drafts 自己每步都 save，落了盘之后
    // 另一个 context 照样 fetch 得到，「共不共用」被「反正都落了盘」盖住了。
    //
    // 真正把 drafts 那一侧区分开的是 `commit`——§4.5 第 1 条要求「写流水」与
    // 「删草稿」进**同一次 save**，为此 `DraftStore.commit` 用的是 `ledger.stage()`
    // （只 insert 不落盘）加自己那一次 `save()`。两者若不共用 context，
    // 那笔流水插进了 ledger 的 context，而 drafts 保存的是自己的——
    // **流水永远不落盘，用户这一坐凭空消失**，而草稿倒是删干净了。
    //
    // 而且得**另开一个 context 去问**：`includePendingChanges` 默认 true，
    // 拿 ledger 自己的 context 查，那笔没落盘的照样看得见（本仓库实测）。
    // 实测印证：把 drafts 换成新 context，红的只有底下那一句 `旁观`。
    let 待提交 = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(待提交, amount: 108, at: now)
    _ = try env.drafts.commit(待提交, item: item, amount: 108, at: now)

    let 旁观 = ModelContext(env.container)
    #expect(try 旁观.fetch(FetchDescriptor<PracticeSession>()).count == 2,
            "commit 的流水没落盘——drafts 与 ledger 多半不在同一个 context 上")
}

@MainActor
@Test func 装配时带上设备落款() throws {
    let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: defaults)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    let now = Date()
    let s = try env.ledger.record(item: item, amount: 1, source: .counter,
                                  startedAt: now, at: now)
    #expect(!s.deviceName.isEmpty, "没有落款，第 3 卷诊断页就说不出这笔是哪台设备记的")
    #expect(s.deviceName == DeviceIdentity.displayName(defaults: defaults))
}

@MainActor
@Test func 装配会带出设置() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    #expect(env.settings.soundEnabled)
    #expect(env.settings.dayStartHour == 0)
}

@MainActor
@Test func 启动清账在装配阶段不自动跑() throws {
    // 清账必须由 RootView 在明确的时机调用（Task 19），
    // 藏在构造函数里会让「什么时候动了用户数据」变得说不清。
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    let d = try env.drafts.begin(itemID: item.id, source: .counter, at: Date())
    try env.drafts.update(d, amount: 50, at: Date())

    // 再装配一次：这一次构造函数面对的是一个**已有半截草稿**的库。
    _ = try AppEnvironment(container: env.container,
                           defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)

    #expect(try env.drafts.pendingDrafts().count == 1, "构造函数不该动草稿")

    // **纪律第 2 条：「什么都不该写」要写「库里一条都没有」。**
    // 只查草稿数的话，一个「顺手把今天的快照先建好」的构造函数照样绿——
    // 而那正是 §5.6 那个坑的形状：CloudKit 只同步到一半时启动，
    // 会拿此刻本机看得见的定课集合给今天**永久定格**一份残缺快照，
    // 且「已存在则沿用、绝不覆盖」意味着再也改不回来。
    #expect(try env.context.fetch(FetchDescriptor<PracticeSession>()).isEmpty,
            "构造函数写了流水")
    #expect(try env.context.fetch(FetchDescriptor<DaySnapshot>()).isEmpty,
            "构造函数建了快照——§5.6 的坑就是这么踩的")

    // 上面三句查的是草稿、流水、快照，**独独漏了 `PracticeItem`**——于是一个
    // 「首次启动看库是空的，顺手把内置定课装上」的构造函数全程隐形。
    // 那个形状比建快照更险：CloudKit 只同步到一半时启动，本地看着就是空库，
    // 于是又装一套内置定课。用户回头看见**两个「念佛」**，两个都进 `plan` 的
    // 应做清单——那一天**再也不可能圆满**，而他根本不知道自己做错了什么。
    //
    // 数量而非 isEmpty：这条测试自己上面建了一项。
    #expect(try env.context.fetch(FetchDescriptor<PracticeItem>()).count == 1,
            "构造函数自己建了功课——同步只到一半时启动，用户会看见两份同名定课")
}
