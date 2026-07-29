import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeToday() throws -> (TodayViewModel, PracticeItemStore, DayLedger, ModelContext) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let ledger = DayLedger(context: ctx, deviceName: "iPhone·TEST")
    let items = PracticeItemStore(context: ctx)
    return (TodayViewModel(ledger: ledger, items: items), items, ledger, ctx)
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
@Test func 没有定课时是无课日而不是未圆满() throws {
    // §6.8 三态：应做集合为空叫「无课」，不计入分母，也不中断。
    // 把它算成「未圆满」就是在用户什么都没安排的日子里给他记一笔失败。
    let (vm, _, _, _) = try makeToday()
    try vm.reload(now: 北京(7, 28, 9, 0), timeZone: 北京时间)
    #expect(vm.rows.isEmpty)
    #expect(vm.isRestDay)
    #expect(!vm.isFulfilled, "无课日不该被说成圆满")
    #expect(vm.dayKey == 20260728)
}

@MainActor
@Test func 列出今日应做并带上当前进度() throws {
    let (vm, items, ledger, _) = try makeToday()
    let item = try items.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: 1000, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 300, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)

    try vm.reload(now: now, timeZone: 北京时间)

    #expect(vm.rows.count == 1)
    let row = vm.rows[0]
    #expect(row.name == "念佛")
    #expect(row.unit == "声")
    #expect(row.total == 300)
    #expect(row.goal == 1000)
    #expect(row.state == .pending)
    #expect(abs(row.progress - 0.3) < 0.0001)
    #expect(!vm.isFulfilled)
    #expect(!vm.isRestDay)
}

@MainActor
@Test func 达标后转为圆满且进度封顶在一() throws {
    let (vm, items, ledger, _) = try makeToday()
    let item = try items.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: 1000, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 3000, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)
    try vm.reload(now: now, timeZone: 北京时间)
    #expect(vm.rows[0].state == .fulfilled)
    #expect(vm.rows[0].progress == 1.0, "超额完成时进度不该超过 1")
    #expect(vm.rows[0].total == 3000, "总数照实显示，封顶的只是进度条")
    #expect(vm.isFulfilled)
}

@MainActor
@Test func 不设目标时做了就算圆满() throws {
    let (vm, items, ledger, _) = try makeToday()
    let item = try items.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: nil, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    let now = 北京(7, 28, 9, 0)
    try vm.reload(now: now, timeZone: 北京时间)
    #expect(vm.rows[0].state == .pending)
    #expect(vm.rows[0].progress == 0)
    #expect(vm.rows[0].goal == nil)

    try ledger.record(item: item, amount: 1, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)
    try vm.reload(now: now, timeZone: 北京时间)
    #expect(vm.rows[0].state == .fulfilled, "无目标 = 做了就算圆满")
    #expect(vm.rows[0].progress == 1.0)
}

@MainActor
@Test func 按用户拖拽的顺序显示而不是按uuid() throws {
    // DayPlan.requiredItemIDs 是按 uuidString 排的（为了跨设备逐位一致），
    // 直接拿来显示会让用户看到一个每次都可能不同、且与他自己排的顺序无关的清单。
    let (vm, items, _, _) = try makeToday()
    let a = try items.create(from: TemplateCatalog.template(key: "chanting")!)
    let b = try items.create(from: TemplateCatalog.template(key: "mantra")!)
    let c = try items.create(from: TemplateCatalog.template(key: "sutra")!)
    try items.reorder([c, a, b])

    try vm.reload(now: 北京(7, 28, 9, 0), timeZone: 北京时间)
    #expect(vm.rows.map(\.name) == ["诵经", "念佛", "持咒"])
    _ = (a, b, c)
}

@MainActor
@Test func 当天归档的功课仍留在清单上并标注已归档() throws {
    // 与第 5 卷月历读同一份快照，两处口径必须一致。
    // 藏起来的话今日页会说「圆满」而月历会说「没圆满」。
    let (vm, items, _, _) = try makeToday()
    let 念佛 = try items.create(from: TemplateCatalog.template(key: "chanting")!)
    let 拜佛 = try items.create(from: TemplateCatalog.template(key: "prostrate")!)
    let now = 北京(7, 28, 9, 0)
    try vm.reload(now: now, timeZone: 北京时间)
    #expect(vm.rows.count == 2, "前提：上午两项都在")

    try items.archive(拜佛, at: 北京(7, 28, 12, 0))
    try vm.reload(now: 北京(7, 28, 13, 0), timeZone: 北京时间)

    #expect(vm.rows.count == 2, "当日快照已经登记了拜佛，藏起来会与月历口径打架")
    let 拜 = vm.rows.first { $0.itemID == 拜佛.id }
    #expect(拜?.isArchived == true, "要标注出来，让用户知道它明天就不出现了")
    #expect(vm.rows.first { $0.itemID == 念佛.id }?.isArchived == false)
    #expect(vm.rows.last?.itemID == 拜佛.id, "已归档的排到最后")
}

@MainActor
@Test func 第二天归档的功课就不再出现() throws {
    let (vm, items, _, _) = try makeToday()
    try items.create(from: TemplateCatalog.template(key: "chanting")!)
    let 拜佛 = try items.create(from: TemplateCatalog.template(key: "prostrate")!)
    try items.archive(拜佛, at: 北京(7, 28, 12, 0))

    try vm.reload(now: 北京(7, 29, 9, 0), timeZone: 北京时间)

    #expect(vm.dayKey == 20260729)
    #expect(vm.rows.count == 1, "只唠叨到当天为止")
    #expect(vm.rows[0].name == "念佛")
}

@MainActor
@Test func 全部达标才算今日圆满() throws {
    let (vm, items, ledger, _) = try makeToday()
    let a = try items.create(name: "念佛", measureType: .count, unit: "声",
                             dailyGoal: 100, iconName: "circle.grid.3x3",
                             colorHex: Palette.Light.fulfilled)
    let b = try items.create(name: "拜佛", measureType: .count, unit: "拜",
                             dailyGoal: 108, iconName: "figure.stand",
                             colorHex: Palette.Light.fulfilled)
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: a, amount: 100, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)
    try vm.reload(now: now, timeZone: 北京时间)
    #expect(!vm.isFulfilled, "还差一项")

    try ledger.record(item: b, amount: 108, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)
    try vm.reload(now: now, timeZone: 北京时间)
    #expect(vm.isFulfilled)
}

@MainActor
@Test func 一日起始时间会改变今天是哪天() throws {
    let (vm, items, _, _) = try makeToday()
    try items.create(from: TemplateCatalog.template(key: "chanting")!)
    let 凌晨两点 = 北京(7, 29, 2, 0)
    try vm.reload(now: 凌晨两点, dayStartHour: 0, timeZone: 北京时间)
    #expect(vm.dayKey == 20260729)
    try vm.reload(now: 凌晨两点, dayStartHour: 3, timeZone: 北京时间)
    #expect(vm.dayKey == 20260728, "夜课修到凌晨的用户希望算作昨天")
}

@MainActor
@Test func 计时类的进度按秒算() throws {
    let (vm, items, ledger, _) = try makeToday()
    let item = try items.create(name: "打坐", measureType: .duration, unit: "",
                                dailyGoal: 1800, iconName: "figure.mind.and.body",
                                colorHex: Palette.Light.fulfilled)
    let now = 北京(7, 28, 6, 0)
    try ledger.record(item: item, amount: 900, source: .timer,
                      startedAt: now, at: now, timeZone: 北京时间)
    try vm.reload(now: now, timeZone: 北京时间)
    #expect(vm.rows[0].measureType == .duration)
    #expect(vm.rows[0].total == 900)
    #expect(abs(vm.rows[0].progress - 0.5) < 0.0001)
}

@MainActor
@Test func 重新载入不会重复生成快照() throws {
    // reload 会走 plan(for:activeItems:)，它在无快照时才落库。
    // 若每次 reload 都新增一条，一天下来 CloudKit 上会堆几十条同日快照。
    let (vm, items, _, ctx) = try makeToday()
    try items.create(from: TemplateCatalog.template(key: "chanting")!)
    let now = 北京(7, 28, 9, 0)
    for _ in 0..<5 { try vm.reload(now: now, timeZone: 北京时间) }
    let snapshots = try ctx.fetch(FetchDescriptor<DaySnapshot>())
    #expect(snapshots.count == 1, "同一天只该有一条本机生成的快照，实际 \(snapshots.count)")
}
