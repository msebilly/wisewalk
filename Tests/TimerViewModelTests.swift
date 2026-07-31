import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeTimer(goal: Int? = 1800) throws
    -> (TimerViewModel, DraftStore, DayLedger, PracticeItem, ModelContext) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let ledger = DayLedger(context: ctx, deviceName: "iPhone·TEST")
    let drafts = DraftStore(context: ctx, ledger: ledger)
    let items = PracticeItemStore(context: ctx)
    let item = try items.create(name: "打坐", measureType: .duration, unit: "",
                                dailyGoal: goal, iconName: "figure.mind.and.body",
                                colorHex: Palette.Light.fulfilled)
    return (TimerViewModel(item: item, drafts: drafts, ledger: ledger), drafts, ledger, item, ctx)
}

/// 库里**一条流水都没有**——不限哪一天。
///
/// 写成 `ledger.sessions(on: 20260728, …).isEmpty` 是不够的：那只看一天。
/// 实现要是把流水写到别的日子上——最自然的走样就是退回 `TimeZone.current`——
/// 碎账就从指缝里漏过去，测试照绿（Task 9 实测：在西八区的开发机上，
/// 三条守「中途不写账」的测试对这个走样一条都不红）。
private func 库里一条流水都没有(_ ctx: ModelContext) throws -> Bool {
    try ctx.fetch(FetchDescriptor<PracticeSession>()).isEmpty
}

private let 北京时间 = TimeZone(identifier: "Asia/Shanghai")!

private func 北京(_ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = 北京时间
    return cal.date(from: c)!
}

@MainActor
@Test func 时长按时间戳差值算而不是靠滴答累加() throws {
    // §6.3。App 一进后台 Timer 就停，靠累加滴答会少记一大截——
    // 用户打坐半小时，锁屏放兜里，回来只记了三分钟。
    let (vm, _, _, _, _) = try makeTimer()
    let start = 北京(7, 28, 6, 0)
    try vm.start(at: start, timeZone: 北京时间)
    #expect(vm.elapsed == 0)

    // 中间一次 refresh 都不调，直接跳到二十分钟后
    vm.refresh(at: 北京(7, 28, 6, 20))
    #expect(vm.elapsed == 1200, "少记了——说明用的不是时间戳差值")
}

@MainActor
@Test func 计时中一笔流水都不写() throws {
    let (vm, _, _, _, ctx) = try makeTimer()
    let start = 北京(7, 28, 6, 0)
    try vm.start(at: start, timeZone: 北京时间)
    for m in 1...10 {
        vm.refresh(at: 北京(7, 28, 6, m))
        // 心跳也要走一遍：它是这条路上**唯一**会写盘的动作。
        // 只 refresh 不心跳的话，「把心跳实现成往账本记一笔」这种走样根本碰不着。
        try vm.heartbeatIfNeeded(at: 北京(7, 28, 6, m))
    }
    #expect(try 库里一条流水都没有(ctx))
}

@MainActor
@Test func 心跳按间隔打不是每次refresh都写盘() throws {
    let (vm, drafts, _, item, _) = try makeTimer()
    let start = 北京(7, 28, 6, 0)
    try vm.start(at: start, timeZone: 北京时间)

    try vm.heartbeatIfNeeded(at: 北京(7, 28, 6, 0, 3))
    #expect(try drafts.draft(for: item.id)?.updatedAt == start, "才过 3 秒，不该打心跳")

    let 到点 = start.addingTimeInterval(TimerViewModel.heartbeatInterval)
    try vm.heartbeatIfNeeded(at: 到点)
    #expect(try drafts.draft(for: item.id)?.updatedAt == 到点, "到间隔了就该打")
}

@MainActor
@Test func 心跳不动起始时刻() throws {
    let (vm, drafts, _, item, _) = try makeTimer()
    let start = 北京(7, 28, 6, 0)
    try vm.start(at: start, timeZone: 北京时间)
    try vm.heartbeatIfNeeded(at: 北京(7, 28, 6, 30))
    #expect(try drafts.draft(for: item.id)?.startedAt == start)
    vm.refresh(at: 北京(7, 28, 6, 30))
    #expect(vm.elapsed == 1800)
}

@MainActor
@Test func 结束时按秒记一笔() throws {
    let (vm, drafts, ledger, item, _) = try makeTimer()
    let start = 北京(7, 28, 6, 0)
    let end = 北京(7, 28, 6, 30)
    try vm.start(at: start, timeZone: 北京时间)
    let s = try vm.finish(at: end)
    #expect(s?.amount == 1800, "计时类一律存秒")
    #expect(s?.source == .timer)
    #expect(s?.startedAt == start)
    #expect(s?.endedAt == end)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 1800)
    #expect(try drafts.pendingDrafts().isEmpty)
    #expect(!vm.isRunning)
}

@MainActor
@Test func 不足一秒就结束不留空账() throws {
    let (vm, drafts, _, _, ctx) = try makeTimer()
    let start = 北京(7, 28, 6, 0)
    try vm.start(at: start, timeZone: 北京时间)
    let s = try vm.finish(at: start.addingTimeInterval(0.4))
    #expect(s == nil)
    #expect(try 库里一条流水都没有(ctx))
    #expect(try drafts.pendingDrafts().isEmpty)
}

@MainActor
@Test func 重复按结束不会记两坐() throws {
    let (vm, _, ledger, item, _) = try makeTimer()
    let start = 北京(7, 28, 6, 0)
    try vm.start(at: start, timeZone: 北京时间)
    try vm.finish(at: 北京(7, 28, 6, 10))
    let second = try vm.finish(at: 北京(7, 28, 6, 20))
    #expect(second == nil)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 600)
}

@MainActor
@Test func 放弃这一坐则草稿与账本都不留痕() throws {
    let (vm, drafts, _, _, ctx) = try makeTimer()
    try vm.start(at: 北京(7, 28, 6, 0), timeZone: 北京时间)
    // 打满四十分钟心跳再放弃——崩溃恢复靠心跳，心跳若污了账本，这里就该炸。
    for m in 1...40 {
        vm.refresh(at: 北京(7, 28, 6, m))
        try vm.heartbeatIfNeeded(at: 北京(7, 28, 6, m))
    }
    try vm.abandon()
    #expect(try drafts.pendingDrafts().isEmpty)
    #expect(try 库里一条流水都没有(ctx))
    #expect(!vm.isRunning)
    #expect(vm.elapsed == 0)
}

@MainActor
@Test func 时钟文本随走时更新() throws {
    let (vm, _, _, _, _) = try makeTimer()
    try vm.start(at: 北京(7, 28, 6, 0), timeZone: 北京时间)
    #expect(vm.clockText == "0:00")
    vm.refresh(at: 北京(7, 28, 6, 1, 5))
    #expect(vm.clockText == "1:05")
    vm.refresh(at: 北京(7, 28, 7, 1, 5))
    #expect(vm.clockText == "1:01:05")
}

@MainActor
@Test func 今日总时长把先前坐过的算进来() throws {
    // 副标题要说「今天一共坐了多久」。只看本次的话，
    // 早上坐过一轮、晚上再坐时会显示得比实际少一大截。
    let (vm, drafts, ledger, item, _) = try makeTimer()
    let 早上 = 北京(7, 28, 6, 0)
    try ledger.record(item: item, amount: 900, source: .timer,
                      startedAt: 早上, at: 早上, timeZone: 北京时间)

    try vm.start(at: 北京(7, 28, 20, 0), timeZone: 北京时间)
    #expect(vm.committedTotal == 900)
    #expect(vm.dayTotal == 900)
    vm.refresh(at: 北京(7, 28, 20, 10))
    #expect(vm.dayTotal == 1500, "早上的 15 分钟不能漏掉")

    _ = try vm.finish(at: 北京(7, 28, 20, 10))
    #expect(vm.dayTotal == 1500, "记完账后总数不该跳变")

    let 第二轮 = TimerViewModel(item: item, drafts: drafts, ledger: ledger)
    try 第二轮.start(at: 北京(7, 28, 21, 0), timeZone: 北京时间)
    #expect(第二轮.committedTotal == 1500)
}

@MainActor
@Test func 进入已有草稿的计时器接着上次的时刻() throws {
    let (vm, drafts, ledger, item, _) = try makeTimer()
    let start = 北京(7, 28, 6, 0)
    try vm.start(at: start, timeZone: 北京时间)

    let reopened = TimerViewModel(item: item, drafts: drafts, ledger: ledger)
    try reopened.start(at: 北京(7, 28, 6, 15), timeZone: 北京时间)
    #expect(reopened.elapsed == 900, "起始时刻必须沿用草稿的，不是重新开始")
    #expect(try drafts.pendingDrafts().count == 1)
}

@MainActor
@Test func 回到前台重新start会重读今日已记且不重新计时() throws {
    // Task 16 的计时页靠 `start()` 当 reload 用：熄屏期间日子可能翻过去了，
    // 别处记的流水也可能同步进来。所以 `start()` 必须**可以重复调**，
    // 而且第二次调要真的去重读账本。
    //
    // 这条同时挡住两件事：谁若给 `start()` 加个「已经在跑就直接返回」的短路，
    // reload 就废了；谁若让它把 `startedAt` 换成「现在」，已经坐的就归零了。
    let (vm, drafts, ledger, item, _) = try makeTimer()
    let start = 北京(7, 28, 6, 0)
    try vm.start(at: start, timeZone: 北京时间)
    vm.refresh(at: 北京(7, 28, 6, 20))
    #expect(vm.committedTotal == 0)
    #expect(vm.elapsed == 1200)

    // 熄屏期间：另一台设备同步进来一坐，或者用户在补记页记了一笔
    try ledger.record(item: item, amount: 900, source: .manual,
                      startedAt: start, at: start, timeZone: 北京时间)

    try vm.start(at: 北京(7, 28, 6, 20), timeZone: 北京时间)

    #expect(vm.elapsed == 1200, "已经坐的 20 分钟不能归零")
    #expect(vm.committedTotal == 900, "reload 必须看见别处记的那 15 分钟")
    #expect(vm.dayTotal == 2100)
    #expect(try drafts.pendingDrafts().count == 1, "不该多出一份草稿")

    try vm.finish(at: 北京(7, 28, 6, 20))
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 2100, "一秒不多不少")
}

@MainActor
@Test func 落哪天按收坐那一刻算而不是起坐那一刻() throws {
    // 夜坐跨零点。dayKey 由 finish 那一刻推导，不是由起坐那一刻。
    // 这条规矩若没有测试钉住，把 `DraftStore.commit` 的 `at: now`
    // 换成 `at: draft.startedAt` 会全卷全绿（Task 9 实测过）。
    let (vm, _, ledger, item, _) = try makeTimer()
    try vm.start(at: 北京(7, 28, 23, 40), timeZone: 北京时间)
    try vm.finish(at: 北京(7, 29, 0, 10))
    #expect(try ledger.total(on: 20260729, itemID: item.id) == 1800, "一日起始是 0，零点十分就该算 29 号")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func 坐过零点后屏幕上的今日不带昨天的数() throws {
    // 夜坐 23:40 起坐，坐到次日 0:10 结束。
    // `committedTotal` 是**进页面那一刻那一天**的数，流水却落在**结束那一刻**那一天。
    // 无脑 `+=` 就把昨天早课那 3600 秒算进了「今日」，副标题报 5400 秒——
    // 今天其实只坐了 1800 秒。账本一秒不多不少，说谎的是屏幕。
    //
    // 这是「一声都不能多」的另一种犯法：报告层替用户宣布了他没做到的事。
    let (vm, _, ledger, item, _) = try makeTimer()
    let 昨晨 = 北京(7, 28, 6, 0)
    try ledger.record(item: item, amount: 3600, source: .timer,
                      startedAt: 昨晨, at: 昨晨, timeZone: 北京时间)
    try vm.start(at: 北京(7, 28, 23, 40), timeZone: 北京时间)
    #expect(vm.dayTotal == 3600)

    try vm.finish(at: 北京(7, 29, 0, 10))

    #expect(vm.dayTotal == 1800, "日子翻过去了，屏幕上的『今日』不该再带着昨天那一小时")
    #expect(vm.dayRounds == 1, "坐数同理：29 号只坐了这一坐，副标题不许把 28 号早课那一坐算进来")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 3600)
    #expect(try ledger.total(on: 20260729, itemID: item.id) == 1800)
}

@MainActor
@Test func 收坐时用的是进页面时那个时区() throws {
    // 「一日起始」与时区在 `start()` 时存住，`finish()` 不再单收——
    // 两处各收各的、传得不一致时，`committedTotal` 算的是 A 天、流水写进 B 天，
    // 屏幕上的 `dayTotal` 就成了哪一天都对不上的游离数字。
    // Task 16 的规格正是这么写的：`start(dayStartHour: settings.dayStartHour)`
    // 而 `finish()` 什么都不传，两边差着用户设的那个一日起始。
    //
    // 构造上**不受开发机时区影响**：直觉写法「传北京时间再断言落在哪天」要指望
    // `.current` 碰巧不等于北京时间，在东八区的机器上必然假绿。
    // 改成同一时刻跑两遍，喂两个**相差整 24 小时**的固定偏移时区：
    // 只要 finish 认的是存下来的时区，两边必然落在相邻两天；
    // 若它退回 `.current`，两边用同一个时区、落在同一天——不管本机在哪儿这条都红。
    // 用固定偏移而不是地名时区，是为了躲开夏令时。
    let 东十三 = TimeZone(secondsFromGMT: 13 * 3600)!
    let 西十一 = TimeZone(secondsFromGMT: -11 * 3600)!
    let 起 = 北京(7, 28, 12, 0)
    let 收 = 北京(7, 28, 12, 30)

    func 落在哪天(_ tz: TimeZone) throws -> Int {
        let (vm, _, ledger, item, _) = try makeTimer()
        try vm.start(at: 起, timeZone: tz)
        try vm.finish(at: 收)
        let 有账的那天 = try [20260727, 20260728, 20260729]
            .filter { try ledger.total(on: $0, itemID: item.id) == 1800 }
        #expect(有账的那天.count == 1, "这一坐必须且只能落在一天上")
        return 有账的那天[0]
    }

    let 早 = try 落在哪天(东十三)
    let 晚 = try 落在哪天(西十一)
    #expect(早 == 20260728)
    #expect(晚 == 20260727)
    #expect(早 != 晚, "同一时刻、相差整日的两个时区，不该落在同一天")
}

@MainActor
@Test func 时钟回拨时走时不为负() throws {
    let (vm, _, _, _, _) = try makeTimer()
    try vm.start(at: 北京(7, 28, 6, 0), timeZone: 北京时间)
    vm.refresh(at: 北京(7, 28, 5, 0))
    #expect(vm.elapsed == 0)
    #expect(vm.clockText == "0:00")
}

@MainActor
@Test func 未开始时刷新与心跳都是空操作() throws {
    let (vm, drafts, _, _, _) = try makeTimer()
    vm.refresh(at: 北京(7, 28, 6, 0))
    try vm.heartbeatIfNeeded(at: 北京(7, 28, 6, 30))
    #expect(vm.elapsed == 0)
    #expect(!vm.isRunning)
    #expect(try drafts.pendingDrafts().isEmpty)
}

@MainActor
@Test func 坐了八小时多半是忘了按结束不自动记账() throws {
    // 早课六点起坐，忘了按结束，晚上才想起来打开 App。
    // App 若被系统回收过，下次启动的恢复弹窗会按心跳止步处问「记 20 秒吗」；
    // App 只是挂起的话，回前台 start() 照单全收那份草稿，refresh 直接给出
    // 十几个小时——同一组事实，分叉点只是 iOS 有没有恰好回收这个进程。
    // 账本这边一秒都不许动：不落账、不清草稿、抛错让界面去问。
    let (vm, drafts, _, item, ctx) = try makeTimer()
    try vm.start(at: 北京(7, 28, 6, 0), timeZone: 北京时间)

    #expect(throws: TimerViewModelError.implausibleDuration(seconds: 30600)) {
        try vm.finish(at: 北京(7, 28, 14, 30))
    }

    #expect(try 库里一条流水都没有(ctx), "编一个数记上去，比什么都不记坏得多")
    #expect(try drafts.draft(for: item.id) != nil, "草稿要原样留着——问的过程中 App 死了还能恢复")
    #expect(vm.isRunning, "还没了结，别把页面状态清了")
}

@MainActor
@Test func 四小时整还算数多一秒才拦() throws {
    // 阈值本身必须落在「记」这一侧：禅七长坐坐满四个钟头是真事。
    let 起 = 北京(7, 28, 6, 0)
    let (刚好, _, ledger1, item1, _) = try makeTimer(goal: nil)
    try 刚好.start(at: 起, timeZone: 北京时间)
    try 刚好.finish(at: 起.addingTimeInterval(4 * 3600))
    #expect(try ledger1.total(on: 20260728, itemID: item1.id) == 14400)

    let (多一秒, _, _, _, ctx2) = try makeTimer(goal: nil)
    try 多一秒.start(at: 起, timeZone: 北京时间)
    #expect(throws: TimerViewModelError.implausibleDuration(seconds: 14401)) {
        try 多一秒.finish(at: 起.addingTimeInterval(4 * 3600 + 1))
    }
    #expect(try 库里一条流水都没有(ctx2))
}

@MainActor
@Test func 问出实际时长之后按用户给的那个数记账() throws {
    let (vm, drafts, ledger, item, _) = try makeTimer()
    try vm.start(at: 北京(7, 28, 6, 0), timeZone: 北京时间)
    #expect(throws: TimerViewModelError.self) { try vm.finish(at: 北京(7, 28, 14, 30)) }

    let s = try vm.record(seconds: 1800, at: 北京(7, 28, 14, 30))

    #expect(s?.amount == 1800, "记的是用户说的数，不是计时器上那个")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 1800)
    #expect(vm.dayTotal == 1800)
    #expect(try drafts.pendingDrafts().isEmpty)
    #expect(!vm.isRunning)
}

@MainActor
@Test func 超限之后放弃这一坐则草稿与账本都不留痕() throws {
    let (vm, drafts, _, _, ctx) = try makeTimer()
    try vm.start(at: 北京(7, 28, 6, 0), timeZone: 北京时间)
    #expect(throws: TimerViewModelError.self) { try vm.finish(at: 北京(7, 28, 14, 30)) }

    #expect(try vm.record(seconds: 0, at: 北京(7, 28, 14, 30)) == nil)

    #expect(try 库里一条流水都没有(ctx))
    #expect(try drafts.pendingDrafts().isEmpty)
    #expect(!vm.isRunning)
    #expect(vm.elapsed == 0)
}

@MainActor
@Test func 坐第二回时今日坐数还是一坐等收了才算两坐() throws {
    // 第一坐收了 → dayRounds 1；第二坐还在进行中 → 仍是 1，收了才是 2。
    // 本轮尚未入账，不该把自己算进去；先算进去的实现会在中间那一步给出 2。
    let (vm, _, _, _, _) = try makeTimer()
    #expect(vm.dayRounds == 0, "还没坐过")

    try vm.start(at: 北京(7, 28, 6, 0), timeZone: 北京时间)
    #expect(vm.dayRounds == 0, "第一坐还在进行中，不许先把自己算进去")
    _ = try vm.finish(at: 北京(7, 28, 6, 30))
    #expect(vm.dayRounds == 1)

    try vm.start(at: 北京(7, 28, 20, 0), timeZone: 北京时间)
    #expect(vm.dayRounds == 1, "第二坐还在进行中，仍是一坐")
    _ = try vm.finish(at: 北京(7, 28, 20, 30))
    #expect(vm.dayRounds == 2)
}
