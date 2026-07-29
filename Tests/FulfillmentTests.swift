import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeEnv() throws -> (DayLedger, ModelContext) {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)
    return (DayLedger(context: ctx, deviceName: "iPhone·TEST"), ctx)
}

private let 北京时间 = TimeZone(identifier: "Asia/Shanghai")!

private func 北京(_ mo: Int, _ d: Int, _ h: Int) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = mo; c.day = d; c.hour = h
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = 北京时间
    return cal.date(from: c)!
}

@MainActor
@Test func 首次取快照会依当前定课生成() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    let b = PracticeItem(name: "打坐", measureType: .duration, dailyGoal: nil)
    ctx.insert(a); ctx.insert(b)
    try ctx.save()

    let snap = try ledger.snapshot(for: 20260728, activeItems: [a, b])
    #expect(Set(snap.requiredItemIDs) == [a.id, b.id])
    #expect(snap.goals[a.id.uuidString] == 1000)
    #expect(snap.goals[b.id.uuidString] == nil, "未设目标的项不进 goals 字典")
}

@MainActor
@Test func 快照生成后不因定课变更而改写() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()

    _ = try ledger.snapshot(for: 20260728, activeItems: [a])

    a.dailyGoal = 3000
    try ctx.save()

    let again = try ledger.snapshot(for: 20260728, activeItems: [a])
    #expect(again.goals[a.id.uuidString] == 1000, "过去的日子不许被今天的设置改写")
}

@MainActor
@Test func 重复快照按最早一条为准() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    // CloudKit 不支持唯一约束，两台设备可能各生成一条同日快照。
    let early = DaySnapshot(dayKey: 20260728, requiredItemIDs: [a.id],
                            goals: [a.id.uuidString: 1000],
                            createdAt: Date(timeIntervalSince1970: 1000))
    let late = DaySnapshot(dayKey: 20260728, requiredItemIDs: [a.id],
                           goals: [a.id.uuidString: 9999],
                           createdAt: Date(timeIntervalSince1970: 2000))
    ctx.insert(late); ctx.insert(early)
    try ctx.save()

    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])
    #expect(snap.goals[a.id.uuidString] == 1000, "去重必须确定性地取最早那条")
}

@MainActor
@Test func 排除已归档的定课项() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛")
    let old = PracticeItem(name: "旧功课", isArchived: true)
    ctx.insert(a); ctx.insert(old)
    try ctx.save()

    let snap = try ledger.snapshot(for: 20260728, activeItems: [a, old])
    #expect(snap.requiredItemIDs == [a.id])
}

@MainActor
@Test func 未达目标为待完成() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])

    let now = 北京(7, 28, 9)
    try ledger.record(item: a, amount: 500, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .pending)
}

@MainActor
@Test func 达到目标为圆满() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])

    let now = 北京(7, 28, 9)
    try ledger.record(item: a, amount: 1000, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .fulfilled)
}

@MainActor
@Test func 未设目标时做了就圆满() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "放生", measureType: .check, dailyGoal: nil)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])

    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .pending)

    let now = 北京(7, 28, 9)
    try ledger.record(item: a, amount: 1, source: .manual,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .fulfilled)
}

@MainActor
@Test func 当日不需做的项为无需完成() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛")
    let b = PracticeItem(name: "诵经")
    ctx.insert(a); ctx.insert(b)
    try ctx.save()
    // 只把 a 列入当日清单
    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])

    #expect(try ledger.fulfillment(of: b.id, on: 20260728, snapshot: snap) == .notRequired)
}

@MainActor
@Test func 撤销后从圆满退回待完成() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.snapshot(for: 20260728, activeItems: [a])

    let now = 北京(7, 28, 9)
    let s = try ledger.record(item: a, amount: 1000, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .fulfilled)

    try ledger.revoke(s, at: now, timeZone: 北京时间)
    #expect(try ledger.fulfillment(of: a.id, on: 20260728, snapshot: snap) == .pending)
}
