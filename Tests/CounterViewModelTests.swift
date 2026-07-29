import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeCounter(goal: Int? = 1000) throws
    -> (CounterViewModel, DraftStore, DayLedger, PracticeItem, ModelContext) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let ledger = DayLedger(context: ctx, deviceName: "iPhone·TEST")
    let drafts = DraftStore(context: ctx, ledger: ledger)
    let items = PracticeItemStore(context: ctx)
    let item = try items.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: goal, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    return (CounterViewModel(item: item, drafts: drafts, ledger: ledger), drafts, ledger, item, ctx)
}

/// 库里**一条流水都没有**——不限哪一天。
///
/// 写成 `ledger.sessions(on: 20260728, …).isEmpty` 是不够的：那只看一天。
/// 实现要是把流水写到别的日子上——最自然的走样就是退回 `TimeZone.current`——
/// 碎账就从指缝里漏过去，测试照绿。实测在西八区的开发机上，
/// 「计数过程中一笔流水都不写」「计数中撤销只减草稿不产生调整流水」
/// 「放弃则草稿与账本都不留痕」对这个走样**一条都不红**：北京 7/28 09:00
/// 按 `.current` 落的是 20260727，而断言查的是 20260728；
/// `abandon` 之后账本里躺着 99 笔碎账，测试照样绿。
/// 这几条守的正是 §6.2「结束时才写入」，成败不该取决于开发机在哪个时区。
private func 库里一条流水都没有(_ ctx: ModelContext) throws -> Bool {
    try ctx.fetch(FetchDescriptor<PracticeSession>()).isEmpty
}

private let 北京时间 = TimeZone(identifier: "Asia/Shanghai")!

private func 北京(_ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = 北京时间
    return cal.date(from: c)!
}

@MainActor
@Test func 每点一下加一() throws {
    let (vm, _, _, _, _) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    #expect(vm.count == 0)
    for _ in 0..<3 { try vm.tap(at: now) }
    #expect(vm.count == 3)
}

@MainActor
@Test func 计数过程中一笔流水都不写() throws {
    // §6.2：结束时才写入。中途写会让「念到一半退出去」在账本上留下一串碎账，
    // 第 3 卷的诊断页和第 5 卷的明细页都会被这些碎账淹没。
    let (vm, _, _, _, ctx) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    for _ in 0..<50 { try vm.tap(at: now) }
    #expect(try 库里一条流水都没有(ctx), "中途不该有任何流水")
    #expect(vm.count == 50)
}

@MainActor
@Test func 每点一下都写进草稿() throws {
    // 崩溃时能保住的就是草稿。不写草稿等于「念了两千声，闪退全没了」——
    // 竞品头号差评正是闪退（36.7%）。
    let (vm, drafts, _, item, _) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    try vm.tap(at: now)
    try vm.tap(at: now)
    #expect(try drafts.draft(for: item.id)?.amount == 2)
}

@MainActor
@Test func 批量增加默认一串念珠() throws {
    let (vm, _, _, _, _) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    #expect(vm.batchStep == 108)
    try vm.addBatch(at: now)
    #expect(vm.count == 108)
    vm.setBatchStep(50)
    try vm.addBatch(at: now)
    #expect(vm.count == 158)
}

@MainActor
@Test func 批量步长至少为一() throws {
    let (vm, _, _, _, _) = try makeCounter()
    vm.setBatchStep(0)
    #expect(vm.batchStep == 1)
    vm.setBatchStep(-9)
    #expect(vm.batchStep == 1)
}

@MainActor
@Test func 没开始就点屏幕会报错而不是默默吞掉() throws {
    // `start()` 抛错（磁盘满、store 打不开）之后，页面还在、整屏还可点。
    // 若 `add` 在没有草稿时静默返回，Task 15 的 `perform` 会把它当成功——
    // **响一声、震一下**，而那一下什么都没记上。
    // 念佛的人闭着眼睛靠声音和手感数数，这种假确认他一辈子都发现不了。
    // 抛出去，视图现成的 catch 就接住了，也不会响那声 tick。
    let (vm, _, _, _, ctx) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    #expect(throws: CounterViewModelError.notCounting) { try vm.tap(at: now) }
    #expect(throws: CounterViewModelError.notCounting) { try vm.addBatch(at: now) }
    #expect(throws: CounterViewModelError.notCounting) { try vm.undo(at: now) }
    #expect(vm.count == 0)
    #expect(try 库里一条流水都没有(ctx))
}

@MainActor
@Test func 计数中撤销只减草稿不产生调整流水() throws {
    // 这笔账压根还没记上，无从撤起。
    // 若在这里追加 .adjustment，账本上会出现一笔凭空冒出来的负数。
    let (vm, drafts, _, item, ctx) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    for _ in 0..<5 { try vm.tap(at: now) }
    try vm.undo(at: now)
    #expect(vm.count == 4)
    #expect(try drafts.draft(for: item.id)?.amount == 4)
    #expect(try 库里一条流水都没有(ctx), "不该有 adjustment 流水")
}

@MainActor
@Test func 撤销到零就停住不往负数走() throws {
    // 账本的当日求和**允许为负**——`.adjustment` 流水可正可负
    // （design-spec §3，`:149` 与 `:173`），而各设备的流水各自独立同步，
    // 一笔负的修正完全可能先于它要修正的那笔正数到达（与 §5.6 同一个到达顺序问题）。
    // 但「正在数的这一笔」不可能是负的：它还没进账本，没有任何东西可修正。
    let (vm, _, _, _, _) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    try vm.tap(at: now)
    try vm.undo(at: now)
    try vm.undo(at: now)
    try vm.undo(at: now)
    #expect(vm.count == 0)
}

@MainActor
@Test func 结束时写一笔流水并清掉草稿() throws {
    let (vm, drafts, ledger, item, _) = try makeCounter()
    let start = 北京(7, 28, 9, 0)
    let end = 北京(7, 28, 9, 30)
    try vm.start(at: start, timeZone: 北京时间)
    for _ in 0..<108 { try vm.tap(at: start) }

    let s = try vm.finish(at: end)

    #expect(s?.amount == 108)
    #expect(s?.source == .counter)
    #expect(s?.startedAt == start, "起始时刻取自草稿")
    #expect(s?.endedAt == end)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
    #expect(try drafts.pendingDrafts().isEmpty)
}

@MainActor
@Test func 一声没念就结束不留空账() throws {
    let (vm, drafts, _, _, ctx) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    let s = try vm.finish(at: now)
    #expect(s == nil)
    #expect(try 库里一条流水都没有(ctx))
    #expect(try drafts.pendingDrafts().isEmpty, "空草稿也要清掉，免得下次启动弹恢复窗")
}

@MainActor
@Test func 重复结束不会记两笔() throws {
    let (vm, _, ledger, item, _) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    try vm.tap(at: now)
    try vm.finish(at: now)
    let second = try vm.finish(at: now)
    #expect(second == nil, "第二次结束应当什么也不做")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 1)
}

@MainActor
@Test func 重进计数器接着上次的数() throws {
    let (vm, drafts, ledger, item, _) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    for _ in 0..<30 { try vm.tap(at: now) }

    // 退出去（没有结束，草稿留着），再开一个新的 view model 进来
    let reopened = CounterViewModel(item: item, drafts: drafts, ledger: ledger)
    try reopened.start(at: 北京(7, 28, 10, 0), timeZone: 北京时间)
    #expect(reopened.count == 30, "已经念的 30 声必须还在")
    #expect(try drafts.pendingDrafts().count == 1, "不该多出一份草稿")
}

@MainActor
@Test func 回到前台重新start会重读今日已记且不清零() throws {
    // Task 15 的计数页靠 `start()` 当 reload 用：熄屏一夜再回来，日子可能翻过去了，
    // 别处记的流水也可能同步进来。所以 `start()` 必须**可以重复调**，
    // 而且第二次调要真的去重读账本。
    //
    // 这条同时挡住两件事：谁若给 `start()` 加个 `guard draft == nil else { return }`
    // 当「优化」，reload 就废了；谁若让它重新 begin 一份草稿，已经念的就清零了。
    let (vm, drafts, ledger, item, _) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    for _ in 0..<108 { try vm.tap(at: now) }
    #expect(vm.committedTotal == 0)

    // 熄屏期间：另一台设备同步进来一笔，或者用户在补记页记了一笔
    try ledger.record(item: item, amount: 300, source: .manual,
                      startedAt: now, at: now, timeZone: 北京时间)

    try vm.start(at: now, timeZone: 北京时间)

    #expect(vm.count == 108, "已经念的不能清零")
    #expect(vm.committedTotal == 300, "reload 必须看见别处记的那 300")
    #expect(vm.dayTotal == 408)
    #expect(try drafts.pendingDrafts().count == 1, "不该多出一份草稿")

    try vm.finish(at: now)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 408, "一声不多不少")
}

@MainActor
@Test func 显示今日已记与本次合计() throws {
    // 用户需要知道「今天一共念了多少」，而不只是「这一轮念了多少」。
    let (vm, _, ledger, item, _) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 300, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)
    try vm.start(at: now, timeZone: 北京时间)
    #expect(vm.committedTotal == 300)
    #expect(vm.dayTotal == 300)
    for _ in 0..<50 { try vm.tap(at: now) }
    #expect(vm.count == 50)
    #expect(vm.dayTotal == 350)
    _ = item
}

@MainActor
@Test func 放弃则草稿与账本都不留痕() throws {
    let (vm, drafts, _, _, ctx) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    for _ in 0..<99 { try vm.tap(at: now) }
    try vm.abandon()
    #expect(try drafts.pendingDrafts().isEmpty)
    #expect(try 库里一条流水都没有(ctx))
    #expect(vm.count == 0)
}

@MainActor
@Test func 设了凌晨三点起始零点半仍算前一天() throws {
    // 夜课念到零点之后。dayKey 由 finish 那一刻推导，
    // 再按「一日起始 3:00」把凌晨拨回前一天。
    //
    // ⚠️ 这条**证明不了**「按结束那一刻算」：00:30 减 3 小时回到 7/28，
    // 而开始时刻本来就在 7/28，两条规则在这个构造下得数相同
    // （实测把 `DraftStore.commit` 的 `at: now` 改成 `at: draft.startedAt`，全卷全绿）。
    // 方向那一半由下面「落哪天按结束那一刻算」专管。
    //
    // 「一日起始」是在 start 时传的：它是**设置**，进这个页面时是什么就是什么，
    // finish 不再单收，省得两处传得不一致（见 dayStartHour 属性的注释）。
    let (vm, _, ledger, item, _) = try makeCounter()
    try vm.start(at: 北京(7, 28, 23, 40), dayStartHour: 3, timeZone: 北京时间)
    for _ in 0..<10 { try vm.tap(at: 北京(7, 28, 23, 50)) }
    try vm.finish(at: 北京(7, 29, 0, 30))
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 10, "设了凌晨 3 点起始，零点半该算 28 号")
    #expect(try ledger.total(on: 20260729, itemID: item.id) == 0)
}

@MainActor
@Test func 落哪天按结束那一刻算而不是开始那一刻() throws {
    // 上一条用了「一日起始 3:00」，零点半被拨回前一天，于是「按结束时刻算」
    // 与「按开始时刻算」得数相同，两条规则分不开。
    //
    // 这条把一日起始设回默认的 0：23:40 开始、次日 0:30 结束，两条规则必然分家——
    // 按结束算落次日，按开始算落当日。规矩本身写在 `dayStartHour` 的注释里，
    // 在这条测试之前它没有任何测试保护。
    let (vm, _, ledger, item, _) = try makeCounter()
    try vm.start(at: 北京(7, 28, 23, 40), timeZone: 北京时间)
    for _ in 0..<10 { try vm.tap(at: 北京(7, 28, 23, 50)) }
    try vm.finish(at: 北京(7, 29, 0, 30))
    #expect(try ledger.total(on: 20260729, itemID: item.id) == 10, "一日起始是 0，零点半就该算 29 号")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func 跨零点结束后屏幕上的今日不带昨天的数() throws {
    // 夜课 23:40 进页面，念到次日 0:30 结束。
    // `committedTotal` 是**进页面那一刻那一天**的数，流水却落在**结束那一刻**那一天。
    // 无脑 `+=` 就把昨天的 1000 声算进了「今日」，屏幕报 1108——今天其实只念了 108 声。
    // 账本一声不多不少（7/28 = 1000、7/29 = 108），说谎的是屏幕。
    //
    // 这是「一声都不能多」的另一种犯法：报告层替用户宣布了他没做到的事。
    let (vm, _, ledger, item, _) = try makeCounter()
    let 昨夜 = 北京(7, 28, 23, 40)
    try ledger.record(item: item, amount: 1000, source: .counter,
                      startedAt: 昨夜, at: 昨夜, timeZone: 北京时间)
    try vm.start(at: 昨夜, timeZone: 北京时间)
    #expect(vm.dayTotal == 1000)

    for _ in 0..<108 { try vm.tap(at: 北京(7, 28, 23, 50)) }
    try vm.finish(at: 北京(7, 29, 0, 30))

    #expect(vm.dayTotal == 108, "日子翻过去了，屏幕上的『今日』不该再带着昨天那 1000")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 1000)
    #expect(try ledger.total(on: 20260729, itemID: item.id) == 108)
}

@MainActor
@Test func 今日已记与流水落在同一天() throws {
    // 钉住 Q3 的「一日起始」那一半：committedTotal 算的那天，
    // 必须就是流水最终落的那天。若两处各传各的，屏幕上的 dayTotal 会成为一个
    // 哪一天都对不上的游离数字——账本没错，错的是显示。
    //
    // ⚠️ 这条**只钉得住 dayStartHour，钉不住时区**。删掉 `self.timeZone = timeZone`
    // 时它红不红，取决于开发机的时区碰巧是什么（实测 PDT 机器上不红：
    // 北京 7/29 00:30 在 PDT 是 7/28 09:30，已过 3 点，与北京时间拨回后
    // 恰好都得到 20260728）。时区那一半由下面那条专门管。
    let (vm, _, ledger, item, _) = try makeCounter()
    let 起 = 北京(7, 28, 23, 40)
    try ledger.record(item: item, amount: 300, source: .counter,
                      startedAt: 起, at: 起, dayStartHour: 3, timeZone: 北京时间)
    try vm.start(at: 起, dayStartHour: 3, timeZone: 北京时间)
    #expect(vm.committedTotal == 300, "进来时就该看见今天已记的 300")

    for _ in 0..<108 { try vm.tap(at: 北京(7, 28, 23, 50)) }
    #expect(vm.dayTotal == 408)

    try vm.finish(at: 北京(7, 29, 0, 30))

    #expect(vm.dayTotal == 408, "结束后显示的数不该跳变")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 408,
            "屏幕上的 408 必须就是账本上那一天的 408")
    #expect(try ledger.total(on: 20260729, itemID: item.id) == 0)
}

@MainActor
@Test func 结束时用的是进页面时那个时区() throws {
    // 钉住 Q3 的时区那一半，**且不受开发机时区影响**。
    //
    // 直觉的写法是「传北京时间，断言落在哪天」，但那要指望 `.current`
    // 碰巧不等于北京时间——机器相关，在东八区的机器上必然假绿。
    // 换个构造绕开：同一时刻跑两遍，喂两个**相差整 24 小时**的固定偏移时区。
    // 只要 finish 认的是存下来的时区，两边就必然落在相邻的两天；
    // 若它退回 `.current`，两边用的是同一个时区，就会落在同一天——
    // 那时不管本机是哪个时区，这条都红。
    //
    // 用固定偏移而不是地名时区，是为了躲开夏令时。
    let 东十三 = TimeZone(secondsFromGMT: 13 * 3600)!
    let 西十一 = TimeZone(secondsFromGMT: -11 * 3600)!
    let 同一时刻 = 北京(7, 28, 12, 0)

    func 落在哪天(_ tz: TimeZone) throws -> Int {
        let (vm, _, ledger, item, _) = try makeCounter()
        try vm.start(at: 同一时刻, timeZone: tz)
        try vm.tap(at: 同一时刻)
        try vm.finish(at: 同一时刻)
        let 有账的那天 = try [20260727, 20260728, 20260729]
            .filter { try ledger.total(on: $0, itemID: item.id) == 1 }
        #expect(有账的那天.count == 1, "这一声必须且只能落在一天上")
        return 有账的那天[0]
    }

    let 早 = try 落在哪天(东十三)
    let 晚 = try 落在哪天(西十一)
    #expect(早 == 20260728)
    #expect(晚 == 20260727)
    #expect(早 != 晚, "同一时刻、相差整日的两个时区，不该落在同一天")
}
