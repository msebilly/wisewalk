import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeRecovery() throws -> (RecoveryCoordinator, AppEnvironment, PracticeItem) {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    return (RecoveryCoordinator(env: env), env, item)
}

@MainActor
@Test func 已入账的草稿被静默丢弃不弹窗() throws {
    // 「写流水 + 删草稿」那次 save 跨两个 store 文件，本就没有分布式事务。
    // 流水落了、草稿没删掉时，若不清账，用户会被问「要恢复这 108 声吗」——
    // 点确认就记了两遍，正是 §4.5 要根除的重复写入。
    let (rc, env, item) = try makeRecovery()
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)
    // 流水按草稿的 sessionID 入账，但草稿故意留着
    try env.ledger.record(item: item, amount: 108, source: .counter,
                          startedAt: now, at: now, id: draft.sessionID)

    try rc.runAtLaunch()

    #expect(rc.pending.isEmpty, "已入账的草稿不该拿去问用户")
    #expect(try env.drafts.pendingDrafts().isEmpty, "已入账的草稿该被清掉")
    #expect(try env.ledger.total(on: DayKey.today(), itemID: item.id) == 108, "不能记两遍")
}

@MainActor
@Test func 查不到功课时记上要报错而不是悄悄什么都不做() throws {
    // 从前「草稿不在手里」与「查不到那门功课」并在同一个 guard 里，
    // 两条都是「从 pending 里抹掉、返回」。前者对，后者是「多」的源头：
    //
    //   用户按「记上」→ 弹窗消失、什么都没发生、一个字也没说 → 他以为没记上 →
    //   照着记忆手动补记一遍 → 而草稿还躺在盘上，下次启动弹窗又问同一份 →
    //   他再按一次「记上」→ **这 108 声进了两回账**。
    //
    // 第 3 卷 CloudKit 只同步到一半时够得着：草稿先到、定课后到。
    let (rc, env, item) = try makeRecovery()
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)
    try rc.runAtLaunch()
    #expect(rc.pending.count == 1)

    // 造出「草稿指着的功课当下查不到」：直接从库里抹掉那门课。
    // 生产上 `PracticeItem` 只归档不硬删，这一步模拟的是同步尚未送达。
    env.context.delete(item)
    try env.context.save()

    #expect(throws: RecoveryError.self) { try rc.accept(rc.pending[0]) }
    #expect(rc.pending.count == 1, "报了错就得让他还能再点一次，不许把这一份丢掉")
    #expect(try env.drafts.pendingDrafts().count == 1, "草稿一个字都不许动")
}

@MainActor
@Test func 空草稿不打扰用户() throws {
    // 点开计数器又立刻退出会留下一份 amount 为 0 的草稿。
    let (rc, env, item) = try makeRecovery()
    _ = try env.drafts.begin(itemID: item.id, source: .counter, at: Date())
    try rc.runAtLaunch()
    #expect(rc.pending.isEmpty)
}

@MainActor
@Test func 真的没入账的草稿会拿来问用户() throws {
    let (rc, env, item) = try makeRecovery()
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)

    try rc.runAtLaunch()

    #expect(rc.pending.count == 1)
    #expect(rc.pending.first?.suggestedAmount == 108)
    #expect(rc.pending.first?.itemName == "念佛")
    #expect(rc.pending.first?.amountText == "108 声")
}

@MainActor
@Test func 计时草稿按最后一次心跳估时长不是按现在() throws {
    // App 可能崩在三天前。用「现在 − startedAt」会给用户记上 72 小时的打坐，
    // 而且是记进一个只增不减的账本。
    let (rc, env, item) = try makeRecovery()
    let 打坐 = try env.items.create(name: "打坐", measureType: .duration, unit: "",
                                   dailyGoal: nil, iconName: "figure.mind.and.body",
                                   colorHex: Palette.Light.accent)
    _ = item
    let 三天前 = Date().addingTimeInterval(-3 * 86_400)
    let draft = try env.drafts.begin(itemID: 打坐.id, source: .timer, at: 三天前)
    try env.drafts.touch(draft, at: 三天前.addingTimeInterval(1800))

    try rc.runAtLaunch()

    #expect(rc.pending.count == 1)
    #expect(rc.pending.first?.suggestedAmount == 1800, "该是心跳止步的 30 分，不是三天")
    #expect(rc.pending.first?.amountText == "30 分")
}

@MainActor
@Test func 接受恢复会入账并清掉草稿() throws {
    let (rc, env, item) = try makeRecovery()
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)
    try rc.runAtLaunch()

    try rc.accept(rc.pending[0])

    #expect(try env.ledger.total(on: DayKey.today(), itemID: item.id) == 108)
    #expect(try env.drafts.pendingDrafts().isEmpty)
    #expect(rc.pending.isEmpty)
}

@MainActor
@Test func 隔夜才点头也记在功课发生的那天() throws {
    // 昨晚的早课草稿，今早启动才被点「记上」。
    // 按「用户点头那一刻」算就会记到今天头上：昨天平白少一门、今天平白多一门。
    let (rc, env, item) = try makeRecovery()
    let tz = TimeZone(identifier: "Asia/Shanghai")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let 昨晚八点 = cal.date(from: DateComponents(year: 2026, month: 7, day: 28, hour: 20))!
    let 今早七点 = cal.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 7))!

    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: 昨晚八点)
    try env.drafts.update(draft, amount: 108, at: 昨晚八点.addingTimeInterval(600))
    try rc.runAtLaunch()

    try rc.accept(rc.pending[0], timeZone: tz)
    _ = 今早七点

    #expect(try env.ledger.total(on: 20260728, itemID: item.id) == 108, "该落在功课发生的那天")
    #expect(try env.ledger.total(on: 20260729, itemID: item.id) == 0, "不该落在点头的那天")
}

@MainActor
@Test func 恢复入账认用户设的一日起始() throws {
    // 设 4 点起始的人正是夜课那批人——也正是最容易崩在半夜留下草稿的那批人。
    // 凌晨 1:30 收的早课，在他心里是「昨天」的课。
    // `accept` 若漏读这个设置就静默退回 0 点，把它记到第二天头上：
    // 昨天平白少一门、今天平白多一门。而这一笔是永久写进账本的，
    // 用户只按了「记上」，不会去核对它落在哪天。
    let (rc, env, item) = try makeRecovery()
    let tz = TimeZone(identifier: "Asia/Shanghai")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    env.settings.dayStartHour = 3

    let 起坐 = cal.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 1))!
    let 收坐 = cal.date(from: DateComponents(year: 2026, month: 7, day: 29, hour: 1, minute: 30))!
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: 起坐)
    try env.drafts.update(draft, amount: 108, at: 收坐)
    try rc.runAtLaunch()

    try rc.accept(rc.pending[0], timeZone: tz)

    #expect(try env.ledger.total(on: 20260728, itemID: item.id) == 108,
            "一日从 3 点算起时，凌晨 1:30 还是 28 号的课")
    #expect(try env.ledger.total(on: 20260729, itemID: item.id) == 0,
            "退回 0 点起始就会落在这儿")
}

@MainActor
@Test func 恢复入账用草稿自己的sessionID() throws {
    // 用同一个 id 才幂等：弹窗点两下、或恢复到一半又崩，都不会记两遍。
    let (rc, env, item) = try makeRecovery()
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)
    let sessionID = draft.sessionID
    try rc.runAtLaunch()
    try rc.accept(rc.pending[0])

    #expect(try env.ledger.exists(sessionID: sessionID))
    #expect(try env.ledger.sessions(on: DayKey.today(), itemID: item.id).count == 1)
}

@MainActor
@Test func 拒绝恢复会丢掉草稿且账本不留痕() throws {
    let (rc, env, item) = try makeRecovery()
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)
    try rc.runAtLaunch()

    try rc.discard(rc.pending[0])

    #expect(try env.ledger.sessions(on: DayKey.today(), itemID: item.id).isEmpty)
    #expect(try env.drafts.pendingDrafts().isEmpty)
    #expect(rc.pending.isEmpty)
}

@MainActor
@Test func 多份草稿逐个处理互不干扰() throws {
    let (rc, env, item) = try makeRecovery()
    let 拜佛 = try env.items.create(name: "拜佛", measureType: .count, unit: "拜",
                                   dailyGoal: nil, iconName: "figure.stand",
                                   colorHex: Palette.Light.accent)
    let now = Date()
    let d1 = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(d1, amount: 108, at: now)
    let d2 = try env.drafts.begin(itemID: 拜佛.id, source: .counter, at: now)
    try env.drafts.update(d2, amount: 48, at: now)

    try rc.runAtLaunch()
    #expect(rc.pending.count == 2)

    try rc.accept(rc.pending.first { $0.itemName == "念佛" }!)
    #expect(rc.pending.count == 1)
    #expect(try env.ledger.total(on: DayKey.today(), itemID: item.id) == 108)
    #expect(try env.ledger.total(on: DayKey.today(), itemID: 拜佛.id) == 0)

    try rc.discard(rc.pending[0])
    #expect(rc.pending.isEmpty)
    #expect(try env.ledger.total(on: DayKey.today(), itemID: 拜佛.id) == 0)
}

@MainActor
@Test func 定课已被硬删时的孤儿草稿被丢弃() throws {
    // PracticeItem 只归档不硬删，但同步来的数据不由我们做主。
    // 认不出归属的草稿没法问用户「要恢复吗」——问了他也不知道是什么。
    let (rc, env, item) = try makeRecovery()
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)
    env.context.delete(item)
    try env.context.save()

    try rc.runAtLaunch()

    #expect(rc.pending.isEmpty)
    #expect(try env.drafts.pendingDrafts().isEmpty, "孤儿草稿该被清掉，不能一直留着")
}

@MainActor
@Test func 归档的定课仍可恢复() throws {
    // 归档只是不再出现在今日，不是没做过。崩溃前念的那 108 声得记上。
    let (rc, env, item) = try makeRecovery()
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)
    try env.items.archive(item)

    try rc.runAtLaunch()
    #expect(rc.pending.count == 1)
    try rc.accept(rc.pending[0])
    #expect(try env.ledger.total(on: DayKey.today(), itemID: item.id) == 108)
}

@MainActor
@Test func 量法改过的草稿启动时静默作废不弹窗() throws {
    // `DraftStore.begin` 挡的是「用户又进了计数器」，这条挡「用户重启了 App」。
    // 缺了它：念了 108 声 → 退出计数器（草稿还在）→ 把定课改成打勾类 → 重启 →
    // 弹窗「念佛 108 声，要恢复吗」→ 用户确认 → 108 写进一个只该有 1 的项，
    // 而账本只增不减，改回来还得再写一笔负数。
    let (rc, env, item) = try makeRecovery()
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)
    try env.items.update(item, name: item.name, measureType: .check, unit: "",
                         dailyGoal: nil, iconName: item.iconName, colorHex: item.colorHex)

    try rc.runAtLaunch()
    #expect(rc.pending.isEmpty, "量法都改了，不该再拿旧草稿问用户")
    #expect(try env.drafts.pendingDrafts().isEmpty, "作废的草稿要清掉，不能每次启动都来一遍")
    #expect(try env.ledger.total(on: DayKey.today(), itemID: item.id) == 0, "一个字也不该记")
}

@MainActor
@Test func 推迟裁决不动草稿下次启动还问得出来() throws {
    // ⛔ 这条测试是**手点模拟器点出来的**，当时 363 条全绿。
    //
    // 恢复弹窗只写了「记上」和「不记了」两个按钮，两个都不是 `.cancel` 角色。
    // **SwiftUI 于是自作主张补了第三个**，标题还是系统英文 `Cancel`——
    // 而它的 action 是空的：不改 `pending`，也不动草稿。
    //
    // 那个 alert 的 `isPresented` 当时绑的是 `.constant(!pending.isEmpty)`。
    // SwiftUI 关闭 alert 时会把 `false` 写回 binding，`.constant` 把这次写入丢掉，
    // 于是 binding 永远说「还开着」而 alert 已经拆了——**状态机从此错位**：
    // 遮罩留在屏上，`.disabled(!isReady)` 永不解除，
    // **整个今日页再也点不动，只能杀掉 App**。那 10 声还躺在草稿里。
    //
    // 光把英文 `Cancel` 换成中文治不了病：只要第三条路的 action 什么都不改，
    // 死锁照旧。**第三条路必须真的改变状态**——这就是 `postpone()`。
    //
    // 它要同时满足两件相反的事：
    //   ① `pending` 清空 → binding 落回 false → 遮罩散掉、界面放行（治死锁）
    //   ② 草稿**一个字节都不许动** → 下次启动照旧问得出来（治「丢」）
    let (rc, env, item) = try makeRecovery()
    let now = Date()
    let draft = try env.drafts.begin(itemID: item.id, source: .counter, at: now)
    try env.drafts.update(draft, amount: 108, at: now)
    try rc.runAtLaunch()
    #expect(rc.pending.count == 1, "前提：这一份本该问")

    rc.postpone()

    #expect(rc.pending.isEmpty, "推迟后 pending 必须清空，否则遮罩不散、界面永远点不动")
    #expect(try env.drafts.pendingDrafts().count == 1, "推迟不是丢弃：草稿必须原封不动")
    let 再 = RecoveryCoordinator(env: env)
    try 再.runAtLaunch()
    #expect(再.pending.count == 1, "下次启动必须还问得出来——推迟一笔不等于丢一笔")
    #expect(再.pending.first?.suggestedAmount == 108, "连数目都不许变")
}
