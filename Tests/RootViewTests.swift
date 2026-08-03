import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
@Test func 根视图能实例化() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    _ = RootView(env: env)
}

@MainActor
@Test func 恢复弹窗的文案说清了是哪一项多少量() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)
    let rc = RecoveryCoordinator(env: env)
    try rc.runAtLaunch()

    let msg = RootView.recoveryMessage(rc.pending[0])
    #expect(msg.contains("念佛"))
    #expect(msg.contains("108 声"))
}

@MainActor
@Test func 恢复完成前不放行导航() throws {
    // 顺序依赖：清算没跑完就让用户进计时器，
    // TimerViewModel.start() 会承接那份三天前的草稿接着计时。
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let rc = RecoveryCoordinator(env: env)
    #expect(!rc.didRun)
    #expect(!RootView.isReady(rc), "没跑清算就放行是错的")
    try rc.runAtLaunch()
    #expect(RootView.isReady(rc))
}

@MainActor
@Test func 还有待裁决的草稿时也不放行() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "打坐", measureType: .duration, unit: "",
                                    dailyGoal: nil, iconName: "figure.mind.and.body",
                                    colorHex: Palette.Light.accent)
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .timer, at: now)
    try env.drafts.touch(draft, at: now.addingTimeInterval(600))
    let rc = RecoveryCoordinator(env: env)
    try rc.runAtLaunch()

    #expect(!RootView.isReady(rc), "还有草稿没裁决就进计时器，会接着三天前的计")
    try rc.discard(rc.pending[0])
    #expect(RootView.isReady(rc))
}

@MainActor
@Test func 恢复弹窗说清了这笔会算在哪天() throws {
    // `accept` 把这笔记在**功课发生的那天**（见 `隔夜才点头也记在功课发生的那天`）。
    // 那条守卫是对的，但它带出一个新问题：弹窗若不说是哪天，
    // 用户按完「记上」回到今日页会发现**什么都没变**——
    // 他刚认下的 108 声像是凭空消失了，于是照着记忆再手动补记一遍。
    // 这不是小概率：凡是隔夜、隔天才重开 App 的草稿，全都走这条路。
    // 「一声都不能多」在这里是被一句没说出口的话破掉的。
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    let tz = TimeZone(identifier: "Asia/Shanghai")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let 昨晚收课 = cal.date(from: DateComponents(year: 2026, month: 7, day: 28,
                                              hour: 21, minute: 40))!
    let draft = try env.drafts.begin(itemID: item.id, source: .counter,
                                     at: 昨晚收课.addingTimeInterval(-600))
    try env.drafts.update(draft, amount: 108, at: 昨晚收课)
    let rc = RecoveryCoordinator(env: env)
    try rc.runAtLaunch()

    // 时区显式传进去：本机是 PDT，拿 .current 去量就是拿实现那把尺子量实现。
    let msg = RootView.recoveryMessage(rc.pending[0], timeZone: tz)
    #expect(msg.contains("7月28日"), "不说是哪天，用户按完「记上」会以为没记上，然后再补一遍")
    #expect(msg.contains("21:40"), "说到分，用户才认得出是哪一坐")
}

@MainActor
@Test func 恢复弹窗分得清计数与计时() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let 念佛 = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                   dailyGoal: nil, iconName: "circle.grid.3x3",
                                   colorHex: Palette.Light.fulfilled)
    let 打坐 = try env.items.create(name: "打坐", measureType: .duration, unit: "",
                                   dailyGoal: nil, iconName: "figure.mind.and.body",
                                   colorHex: Palette.Light.accent)
    let now = Date()
    let d1 = try env.drafts.begin(itemID: 念佛.id, source: .counter, at: now)
    try env.drafts.update(d1, amount: 108, at: now)
    let d2 = try env.drafts.begin(itemID: 打坐.id, source: .timer, at: now)
    try env.drafts.touch(d2, at: now.addingTimeInterval(600))
    let rc = RecoveryCoordinator(env: env)
    try rc.runAtLaunch()

    let 数 = RootView.recoveryMessage(rc.pending.first { $0.itemName == "念佛" }!)
    let 时 = RootView.recoveryMessage(rc.pending.first { $0.itemName == "打坐" }!)
    #expect(数.contains("计数") && !数.contains("计时"), "计数的那份不能说成计时")
    #expect(时.contains("计时") && !时.contains("计数"), "计时的那份不能说成计数")
}

@MainActor
@Test func 那一天账上已经有的数要摆进弹窗里() throws {
    // 「有一笔没记上」这句话，在他自己已经补记过之后就成了假话。
    // 而对假话最自然的反应就是点「记上」——同一笔进两回账。
    // 摆一个数出来，判断留给他。
    let p = PendingRecovery(id: UUID(), itemID: UUID(), itemName: "念佛",
                            source: .counter, suggestedAmount: 108, amountText: "108 声",
                            startedAt: Date(timeIntervalSince1970: 1_785_000_000),
                            endedAt: Date(timeIntervalSince1970: 1_785_003_600))
    let tz = TimeZone(identifier: "Asia/Shanghai")!
    let 有 = RootView.recoveryMessage(p, timeZone: tz, alreadyOnBooksText: "108 声")
    #expect(有.contains("已经记了 108 声"), "账上已有的数得说出来")
    #expect(有.contains("另外"), "得说清这是**不含**眼下这一笔的数，否则他以为已经记上了")

    // ⚠️ 只摆事实，不出主意：App 分不清「他补记过这一笔」和「那天另有一坐」。
    // 早课记完 108、晚上又念到 50 时崩溃，那 108 是另一坐，该点的是「记上」。
    for 指手画脚 in ["就点", "请点", "建议", "应该", "不必再记"] {
        #expect(!有.contains(指手画脚), "「\(指手画脚)」是在替他判断——这一处 App 判断不了")
    }

    let 无 = RootView.recoveryMessage(p, timeZone: tz, alreadyOnBooksText: nil)
    #expect(!无.contains("已经记了"), "那天账上什么都没有，就不该无中生有说一句")
    #expect(无.contains("还没记上"), "原来那两句一个字都不能少")
}
