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

@MainActor
@Test func 孤儿流水不计入任何定课项的统计() throws {
    // item == nil 的流水（定课项被硬删后遗留的孤儿）被 sessions(on:itemID:) 里
    // $0.item?.id == itemID 这道过滤挡在所有查询之外：既不出现在任何 sessions 结果，
    // 也不进 total / rawTotal。故 PracticeItem 只能归档（isArchived）、**绝不能硬删**——
    // 一旦硬删，那项的全部历史会从每个统计里凭空蒸发，正是本数据模型要根除的静默丢数。
    // （让孤儿重新现身是第 3 卷诊断的活儿。）
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    // 直接插入一笔孤儿流水（测试夹具，故意绕过 DayLedger 制造 item == nil）。
    let orphan = PracticeSession(
        item: nil,
        dayKey: 20260728,
        tzOffsetMinutes: 480,
        amount: 500,
        startedAt: now,
        endedAt: now,
        source: .manual,
        deviceName: "iPad·TEST",
        createdAt: now
    )
    ctx.insert(orphan)
    try ctx.save()

    // 夹具自检：孤儿确实落库了，测试不是空转。
    #expect(try ctx.fetch(FetchDescriptor<PracticeSession>()).count == 2, "孤儿应已入库")

    let 该项流水 = try ledger.sessions(on: 20260728, itemID: item.id)
    #expect(该项流水.count == 1, "孤儿流水不该出现在任何定课项的 sessions 结果里")
    #expect(该项流水.allSatisfy { $0.id != orphan.id }, "孤儿不该混进该项流水")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108,
            "孤儿的 500 不计入 total，所以 PracticeItem 只能归档不能硬删，否则历史蒸发")
    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == 108,
            "孤儿的 500 也不计入 rawTotal")
}

@MainActor
@Test func 补记到指定日期而写入时间仍为当下() throws {
    // §6.4：dayKey 为所选日期，但 createdAt 必须是真实写入时刻、tzOffsetMinutes 为当前偏移。
    // 「功课发生在哪天」与「这条何时写下」是两件事，不能挤进同一个 at: 参数——
    // 否则补记上周二会连带伪造 createdAt（快照去重排序与第 3 卷诊断都靠它）。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let s = try ledger.record(item: item, amount: 108, source: .manual,
                              startedAt: now, endedAt: now, at: now,
                              timeZone: 北京时间, onDay: 20260721)

    #expect(s.dayKey == 20260721, "应落在所选日期")
    #expect(s.createdAt == now, "createdAt 必须是真实写入时刻，不能被补记日期篡改")
    #expect(s.tzOffsetMinutes == 480, "tzOffsetMinutes 为当前时区偏移")
    #expect(try ledger.total(on: 20260721, itemID: item.id) == 108, "计入所选日期")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0, "不得混进今天的总数")
}

@MainActor
@Test func 不指定补记日期时沿用旧行为() throws {
    // 回归护栏：省略 onDay: 时 dayKey 仍由 at:/dayStartHour/timeZone 推导。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 23, 30)
    let s = try ledger.record(item: item, amount: 1, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    #expect(s.dayKey == 20260728)
    #expect(s.createdAt == now)
}

@MainActor
@Test func stage不落盘而record落盘() throws {
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)

    let staged = try ledger.stage(item: item, amount: 108, source: .counter,
                                  startedAt: now, at: now, timeZone: 北京时间)
    #expect(staged.amount == 108)
    #expect(ctx.hasChanges, "stage 之后应当还有未落盘的改动")

    try ctx.save()
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
}

@MainActor
@Test func stage与record查重逻辑一致() throws {
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let id = UUID()

    let first = try ledger.record(item: item, amount: 100, source: .counter,
                                  startedAt: now, at: now, timeZone: 北京时间, id: id)
    let again = try ledger.stage(item: item, amount: 100, source: .counter,
                                 startedAt: now, at: now, timeZone: 北京时间, id: id)
    try ctx.save()

    #expect(first.id == again.id, "stage 必须和 record 命中同一道查重")
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).count == 1, "查重失效，记出了第二笔")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 100)
}

@MainActor
@Test func stage同样支持补记到指定日期() throws {
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    try ledger.stage(item: item, amount: 50, source: .manual,
                     startedAt: now, at: now, timeZone: 北京时间, onDay: 20260701)
    try ctx.save()
    #expect(try ledger.total(on: 20260701, itemID: item.id) == 50)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func record仍旧自己落盘不需要调用方再save() throws {
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 7, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)
    #expect(!ctx.hasChanges, "record 应当已经落盘，不该留下未保存的改动")
}
