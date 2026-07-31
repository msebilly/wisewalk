import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeToday() throws -> (TodayViewModel, PracticeItemStore, DayLedger) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let ledger = DayLedger(context: ctx, deviceName: "iPhone·TEST")
    let items = PracticeItemStore(context: ctx)
    return (TodayViewModel(ledger: ledger, items: items), items, ledger)
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
private func makeCheckbox(_ items: PracticeItemStore) throws -> PracticeItem {
    try items.create(name: "早课", measureType: .check, unit: "",
                     dailyGoal: 1, iconName: "sun.horizon",
                     colorHex: Palette.Light.accent)
}

@MainActor
@Test func 打勾记一笔并立刻圆满() throws {
    let (vm, items, ledger) = try makeToday()
    let item = try makeCheckbox(items)
    let now = 北京(7, 28, 6, 0)
    try vm.reload(now: now, timeZone: 北京时间)
    #expect(vm.rows.first?.state == .pending)

    try vm.toggleCheckbox(itemID: item.id, at: now, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 1)
    #expect(vm.rows.first?.state == .fulfilled, "打完勾界面要立刻跟上，不用等下次 reload")
}

@MainActor
@Test func 取消打勾是追加负数不是删记录() throws {
    // append-only 是这个 App 的地基。真删记录会让同步冲突时无从对账。
    let (vm, items, ledger) = try makeToday()
    let item = try makeCheckbox(items)
    let now = 北京(7, 28, 6, 0)
    try vm.reload(now: now, timeZone: 北京时间)
    try vm.toggleCheckbox(itemID: item.id, at: now, timeZone: 北京时间)
    try vm.toggleCheckbox(itemID: item.id, at: 北京(7, 28, 6, 1), timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).count == 2,
            "原记录必须还在，取消是追加一笔负数")
    #expect(vm.rows.first?.state == .pending)
}

@MainActor
@Test func 打勾取消再打勾能回到圆满() throws {
    // 撤销用的是幂等键，若键算错，第二次打勾会被当成重复而无声吞掉。
    let (vm, items, ledger) = try makeToday()
    let item = try makeCheckbox(items)
    try vm.reload(now: 北京(7, 28, 6, 0), timeZone: 北京时间)
    try vm.toggleCheckbox(itemID: item.id, at: 北京(7, 28, 6, 0), timeZone: 北京时间)
    try vm.toggleCheckbox(itemID: item.id, at: 北京(7, 28, 6, 1), timeZone: 北京时间)
    try vm.toggleCheckbox(itemID: item.id, at: 北京(7, 28, 6, 2), timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 1)
    #expect(vm.rows.first?.state == .fulfilled)
}

@MainActor
@Test func 对非勾选类调打勾无效() throws {
    // 念佛点一下记 1 声？那是计数器的事，别让今日页也能记数。
    let (vm, items, ledger) = try makeToday()
    let item = try items.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: 1000, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    try vm.reload(now: 北京(7, 28, 6, 0), timeZone: 北京时间)
    try vm.toggleCheckbox(itemID: item.id, at: 北京(7, 28, 6, 0), timeZone: 北京时间)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func 对已归档的项打勾无效() throws {
    // 归档当天该项仍会显示（口径统一），但不该还能往里记。
    let (vm, items, ledger) = try makeToday()
    let item = try makeCheckbox(items)
    let now = 北京(7, 28, 6, 0)
    try vm.reload(now: now, timeZone: 北京时间)
    try items.archive(item, at: 北京(7, 28, 7, 0))
    try vm.reload(now: 北京(7, 28, 8, 0), timeZone: 北京时间)
    #expect(vm.rows.first?.isArchived == true, "前提：归档当天仍显示")

    try vm.toggleCheckbox(itemID: item.id, at: 北京(7, 28, 8, 0), timeZone: 北京时间)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func 取消打勾只撤自己那天的() throws {
    let (vm, items, ledger) = try makeToday()
    let item = try makeCheckbox(items)
    let 昨天 = 北京(7, 27, 6, 0)
    try ledger.record(item: item, amount: 1, source: .manual,
                      startedAt: 昨天, at: 昨天, timeZone: 北京时间)
    let 今天 = 北京(7, 28, 6, 0)
    try vm.reload(now: 今天, timeZone: 北京时间)
    try vm.toggleCheckbox(itemID: item.id, at: 今天, timeZone: 北京时间)
    try vm.toggleCheckbox(itemID: item.id, at: 北京(7, 28, 6, 1), timeZone: 北京时间)

    #expect(try ledger.total(on: 20260727, itemID: item.id) == 1, "昨天的勾不能被今天取消掉")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func 打坐分几回坐的都数进坐数() throws {
    // 3 笔计时流水 → roundCount == 3
    let (vm, items, ledger) = try makeToday()
    let item = try items.create(name: "打坐", measureType: .duration, unit: "",
                                dailyGoal: 1800, iconName: "figure.mind.and.body",
                                colorHex: Palette.Light.fulfilled)
    for h in 6...8 {
        try ledger.record(item: item, amount: 600, source: .timer,
                          startedAt: 北京(7, 28, h, 0), at: 北京(7, 28, h, 0),
                          timeZone: 北京时间, onDay: 20260728)
    }
    #expect(try ledger.roundCount(on: 20260728, itemID: item.id) == 3)

    try vm.reload(now: 北京(7, 28, 9, 0), timeZone: 北京时间)
    #expect(vm.rows.first?.roundCount == 3, "坐数要透传到 TodayRow")
}

@MainActor
@Test func 撤销和修正不算新的一坐() throws {
    // 2 笔计时 + 1 笔负数调整 + 1 笔正数调整 → 仍是 2 坐，而不是 4 坐。
    // 只按条数数的实现在这里会给出 4。
    let (_, items, ledger) = try makeToday()
    let item = try items.create(name: "打坐", measureType: .duration, unit: "",
                                dailyGoal: 1800, iconName: "figure.mind.and.body",
                                colorHex: Palette.Light.fulfilled)
    try ledger.record(item: item, amount: 600, source: .timer,
                      startedAt: 北京(7, 28, 6, 0), at: 北京(7, 28, 6, 0),
                      timeZone: 北京时间, onDay: 20260728)
    try ledger.record(item: item, amount: 900, source: .timer,
                      startedAt: 北京(7, 28, 7, 0), at: 北京(7, 28, 7, 0),
                      timeZone: 北京时间, onDay: 20260728)
    try ledger.record(item: item, amount: -300, source: .adjustment,
                      startedAt: 北京(7, 28, 8, 0), at: 北京(7, 28, 8, 0),
                      timeZone: 北京时间, onDay: 20260728)
    try ledger.record(item: item, amount: 120, source: .adjustment,
                      startedAt: 北京(7, 28, 9, 0), at: 北京(7, 28, 9, 0),
                      timeZone: 北京时间, onDay: 20260728)

    #expect(try ledger.sessions(on: 20260728, itemID: item.id).count == 4, "前提：库里确实是 4 笔")
    #expect(try ledger.roundCount(on: 20260728, itemID: item.id) == 2, "撤销与修正不算新的一坐")
}
