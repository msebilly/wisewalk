import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeLedger() throws -> (DayLedger, ModelContext, PracticeItem) {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)
    let item = PracticeItem(name: "念佛", measureType: .count, unit: "声", dailyGoal: 1000)
    ctx.insert(item)
    try ctx.save()
    return (DayLedger(context: ctx, deviceName: "iPhone·TEST"), ctx, item)
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
@Test func 记一笔后可以查到() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
}

@MainActor
@Test func 多笔累加() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    for amount in [108, 500, 21] {
        try ledger.record(item: item, amount: amount, source: .counter,
                          startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    }
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 629)
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).count == 3)
}

@MainActor
@Test func 撤销是追加负数而非删除() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let original = try ledger.record(item: item, amount: 500, source: .counter,
                                     startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    try ledger.revoke(original, at: now, timeZone: 北京时间)

    let all = try ledger.sessions(on: 20260728, itemID: item.id)
    #expect(all.count == 2, "原记录必须还在，撤销是追加一笔而不是删除")
    #expect(all.contains { $0.id == original.id }, "原记录被删掉了")
    #expect(all.contains { $0.amount == -500 && $0.source == .adjustment })
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func 撤销笔记指向原记录() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let original = try ledger.record(item: item, amount: 500, source: .counter,
                                     startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    let adj = try ledger.revoke(original, at: now, timeZone: 北京时间)
    #expect(adj.note == "revoke:\(original.id.uuidString)")
}

@MainActor
@Test func 重复撤销同一笔只记一次() throws {
    // 崩溃重放或多设备同撤：同一笔的 -amount 只能追加一次。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let a = try ledger.record(item: item, amount: 500, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    try ledger.revoke(a, at: now, timeZone: 北京时间)
    try ledger.revoke(a, at: now, timeZone: 北京时间)

    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == 0, "第二次撤销必须被幂等吞掉")
    let adjustments = try ledger.sessions(on: 20260728, itemID: item.id)
        .filter { $0.source == .adjustment }
    #expect(adjustments.count == 1, "同一笔撤销只应留下一条 .adjustment")
}

@MainActor
@Test func 撤销不会波及同日其他流水() throws {
    // 本 finding 的回归测试：S1、S2 是两笔独立真实修行。
    // 重复撤销 S1 若不幂等，第二笔 -500 会先吃掉 S2 的 300，再被 clamp 掩盖，
    // 显示归零看似合理，实则凭空抹掉了真做过的 300 声。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let s1 = try ledger.record(item: item, amount: 500, source: .counter,
                               startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    try ledger.record(item: item, amount: 300, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    try ledger.revoke(s1, at: now, timeZone: 北京时间)
    try ledger.revoke(s1, at: now, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 300,
            "重复撤销不得吃掉另一笔真实修行")
}

@MainActor
@Test func 孤立的负数调整不被存储层掩盖() throws {
    // 同步偏序：撤销这笔 .adjustment 先于它的原始正记录抵达本机，
    // 此刻账本原值理应为负。rawTotal 必须如实暴露，好让同步 bug 看得见；
    // 只有显示层 displayTotal 才 clamp 到 0。
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let orphan = PracticeSession(
        item: item,
        dayKey: 20260728,
        tzOffsetMinutes: 480,
        amount: -500,
        startedAt: now,
        endedAt: now,
        source: .adjustment,
        deviceName: "iPad·TEST",
        note: "revoke:\(UUID().uuidString)",
        createdAt: now
    )
    ctx.insert(orphan)
    try ctx.save()

    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == -500, "账本原值必须如实为负")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0, "显示层 clamp 到 0")
}

@MainActor
@Test func 记录自动带上日期键与时区() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 23, 30)
    let s = try ledger.record(item: item, amount: 1, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    #expect(s.dayKey == 20260728)
    #expect(s.tzOffsetMinutes == 480)
    #expect(s.deviceName == "iPhone·TEST")
}

@MainActor
@Test func 一日起始为凌晨三点时深夜记录归前一天() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 1, 30)
    let s = try ledger.record(item: item, amount: 1, source: .counter,
                              startedAt: now, endedAt: now, at: now,
                              dayStartHour: 3, timeZone: 北京时间)
    #expect(s.dayKey == 20260727)
}

@MainActor
@Test func 不同天的流水互不干扰() throws {
    let (ledger, _, item) = try makeLedger()
    let d27 = 北京(7, 27, 9, 0)
    let d28 = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 300, source: .counter,
                      startedAt: d27, endedAt: d27, at: d27, timeZone: 北京时间)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: d28, endedAt: d28, at: d28, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260727, itemID: item.id) == 300)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
}

@MainActor
@Test func 不同定课项互不干扰() throws {
    let (ledger, ctx, item) = try makeLedger()
    let other = PracticeItem(name: "持咒", measureType: .count, unit: "遍")
    ctx.insert(other)
    try ctx.save()

    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    try ledger.record(item: other, amount: 21, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
    #expect(try ledger.total(on: 20260728, itemID: other.id) == 21)
}

@MainActor
@Test func 幂等检查能识别已入账的编号() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let known = UUID()
    #expect(try ledger.exists(sessionID: known) == false)

    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间, id: known)
    #expect(try ledger.exists(sessionID: known) == true)
}

@MainActor
@Test func 同一编号重复入账只记一笔() throws {
    // 崩溃恢复场景：草稿携带预生成编号，恢复时若已入账则不可重复写。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let known = UUID()
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间, id: known)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间, id: known)

    #expect(try ledger.sessions(on: 20260728, itemID: item.id).count == 1)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
}

@MainActor
@Test func 计时类流水以秒记账() throws {
    let (ledger, ctx, _) = try makeLedger()
    let sit = PracticeItem(name: "打坐", measureType: .duration, dailyGoal: 1800)
    ctx.insert(sit)
    try ctx.save()

    let start = 北京(7, 28, 5, 0)
    let end = 北京(7, 28, 5, 45)
    try ledger.record(item: sit, amount: Int(end.timeIntervalSince(start)),
                      source: .timer, startedAt: start, endedAt: end,
                      at: end, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: sit.id) == 2700)
}
