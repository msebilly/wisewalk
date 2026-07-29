import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeCounter(goal: Int? = 1000) throws
    -> (CounterViewModel, DraftStore, DayLedger, PracticeItem) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let ledger = DayLedger(context: ctx, deviceName: "iPhone·TEST")
    let drafts = DraftStore(context: ctx, ledger: ledger)
    let items = PracticeItemStore(context: ctx)
    let item = try items.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: goal, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    return (CounterViewModel(item: item, drafts: drafts, ledger: ledger), drafts, ledger, item)
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
    let (vm, _, _, _) = try makeCounter()
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
    let (vm, _, ledger, item) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    for _ in 0..<50 { try vm.tap(at: now) }
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).isEmpty, "中途不该有任何流水")
    #expect(vm.count == 50)
}

@MainActor
@Test func 每点一下都写进草稿() throws {
    // 崩溃时能保住的就是草稿。不写草稿等于「念了两千声，闪退全没了」——
    // 竞品头号差评正是闪退（36.7%）。
    let (vm, drafts, _, item) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    try vm.tap(at: now)
    try vm.tap(at: now)
    #expect(try drafts.draft(for: item.id)?.amount == 2)
}

@MainActor
@Test func 批量增加默认一串念珠() throws {
    let (vm, _, _, _) = try makeCounter()
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
    let (vm, _, _, _) = try makeCounter()
    vm.setBatchStep(0)
    #expect(vm.batchStep == 1)
    vm.setBatchStep(-9)
    #expect(vm.batchStep == 1)
}

@MainActor
@Test func 计数中撤销只减草稿不产生调整流水() throws {
    // 这笔账压根还没记上，无从撤起。
    // 若在这里追加 .adjustment，账本上会出现一笔凭空冒出来的负数。
    let (vm, drafts, ledger, item) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    for _ in 0..<5 { try vm.tap(at: now) }
    try vm.undo(at: now)
    #expect(vm.count == 4)
    #expect(try drafts.draft(for: item.id)?.amount == 4)
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).isEmpty, "不该有 adjustment 流水")
}

@MainActor
@Test func 撤销到零就停住不往负数走() throws {
    // 账本允许为负（那是同步冲突的真实状态），但「正在数的这一笔」不可能是负的。
    let (vm, _, _, _) = try makeCounter()
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
    let (vm, drafts, ledger, item) = try makeCounter()
    let start = 北京(7, 28, 9, 0)
    let end = 北京(7, 28, 9, 30)
    try vm.start(at: start, timeZone: 北京时间)
    for _ in 0..<108 { try vm.tap(at: start) }

    let s = try vm.finish(at: end, timeZone: 北京时间)

    #expect(s?.amount == 108)
    #expect(s?.source == .counter)
    #expect(s?.startedAt == start, "起始时刻取自草稿")
    #expect(s?.endedAt == end)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
    #expect(try drafts.pendingDrafts().isEmpty)
}

@MainActor
@Test func 一声没念就结束不留空账() throws {
    let (vm, drafts, ledger, item) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    let s = try vm.finish(at: now, timeZone: 北京时间)
    #expect(s == nil)
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).isEmpty)
    #expect(try drafts.pendingDrafts().isEmpty, "空草稿也要清掉，免得下次启动弹恢复窗")
}

@MainActor
@Test func 重复结束不会记两笔() throws {
    let (vm, _, ledger, item) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    try vm.tap(at: now)
    try vm.finish(at: now, timeZone: 北京时间)
    let second = try vm.finish(at: now, timeZone: 北京时间)
    #expect(second == nil, "第二次结束应当什么也不做")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 1)
}

@MainActor
@Test func 重进计数器接着上次的数() throws {
    let (vm, drafts, ledger, item) = try makeCounter()
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
@Test func 显示今日已记与本次合计() throws {
    // 用户需要知道「今天一共念了多少」，而不只是「这一轮念了多少」。
    let (vm, _, ledger, item) = try makeCounter()
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
    let (vm, drafts, ledger, item) = try makeCounter()
    let now = 北京(7, 28, 9, 0)
    try vm.start(at: now, timeZone: 北京时间)
    for _ in 0..<99 { try vm.tap(at: now) }
    try vm.abandon()
    #expect(try drafts.pendingDrafts().isEmpty)
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).isEmpty)
    #expect(vm.count == 0)
}

@MainActor
@Test func 跨零点结束时记在开始那天() throws {
    // 夜课念到零点之后。dayKey 由 finish 那一刻推导，
    // 若用户设了「一日起始 3:00」，零点半仍算前一天。
    let (vm, _, ledger, item) = try makeCounter()
    try vm.start(at: 北京(7, 28, 23, 40), timeZone: 北京时间)
    for _ in 0..<10 { try vm.tap(at: 北京(7, 28, 23, 50)) }
    try vm.finish(at: 北京(7, 29, 0, 30), dayStartHour: 3, timeZone: 北京时间)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 10, "设了凌晨 3 点起始，零点半该算 28 号")
    #expect(try ledger.total(on: 20260729, itemID: item.id) == 0)
}
