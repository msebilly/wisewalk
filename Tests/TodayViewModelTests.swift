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
    // DayPlan.requiredItemIDs 在**已有快照**时是按 uuidString 排的
    // （`DayLedger.merge`：多设备并集要逐位一致），直接拿来显示，
    // 用户看到的清单就与他自己排的顺序无关。
    //
    // **必须 reload 两次。** 第一次库里还没有快照，`plan` 走新建路径，
    // `requiredItemIDs` 是 `required.map(\.id)`——本来就是拖拽序，
    // 排序代码在这条路上是个 no-op，删掉它这条测试照样绿。
    // 第二次才走 `existingPlan → merge`，那里才有 uuidString 排序。
    let (vm, items, _, _) = try makeToday()
    let a = try items.create(from: TemplateCatalog.template(key: "chanting")!)
    let b = try items.create(from: TemplateCatalog.template(key: "mantra")!)
    let c = try items.create(from: TemplateCatalog.template(key: "sutra")!)

    // UUID 每次运行都不同。若把拖拽序写成固定的字面量，三项就有 1/6 的概率
    // 碰巧与 uuidString 序一致，这条测试会间歇性地什么都测不出来。
    // 取 uuidString 序的**倒序**当拖拽序，二者必然不同。
    let dragged = Array([a, b, c].sorted { $0.id.uuidString < $1.id.uuidString }.reversed())
    try items.reorder(dragged)

    try vm.reload(now: 北京(7, 28, 9, 0), timeZone: 北京时间)
    try vm.reload(now: 北京(7, 28, 9, 0), timeZone: 北京时间)
    #expect(vm.rows.map(\.name) == dragged.map(\.name))
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
