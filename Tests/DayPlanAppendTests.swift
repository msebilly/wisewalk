import Testing
import SwiftData
import Foundation
@testable import WiseWalk

/// §5.6 写侧定案的守卫：同步迟到的定课要能补回当日应做，
/// 而今天新立的课不许溜进今天。
///
/// 这一组全部用**固定时区 + 固定时刻**，不碰 `.current`、不碰 `Date()`。
/// 本机是 PDT，本卷已经两次因为跟着系统时区跑而假绿。
@MainActor
private func 建() throws -> (DayLedger, ModelContext) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    return (DayLedger(context: ctx, deviceName: "iPhone·TEST"), ctx)
}

private let 北京 = TimeZone(identifier: "Asia/Shanghai")!

private func 时刻(_ mo: Int, _ d: Int, _ h: Int) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = mo; c.day = d; c.hour = h
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = 北京
    return cal.date(from: c)!
}

private func 课(_ name: String, 立于 born: Date, 目标 goal: Int? = nil, 归档 archived: Bool = false) -> PracticeItem {
    let it = PracticeItem(name: name, dailyGoal: goal, createdAt: born)
    it.isArchived = archived
    return it
}

@Test @MainActor func 迟到的定课会被追加进当日应做() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    let 打坐 = 课("打坐", 立于: 时刻(7, 22, 9))
    ctx.insert(念佛); ctx.insert(打坐)

    // 只有念佛在场时先把 7/28 定格了。
    let 初 = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    #expect(初.requiredItemIDs == [念佛.id])

    // 打坐随后同步进来——它 7/22 就立了，7/28 那天本来就该在。
    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)
    #expect(Set(后.requiredItemIDs) == Set([念佛.id, 打坐.id]))
}

@Test @MainActor func 今天新立的定课不会被追加进今天() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    let 诵经 = 课("诵经", 立于: 时刻(7, 28, 15))   // 就是当天下午立的
    ctx.insert(念佛); ctx.insert(诵经)

    _ = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 诵经], dayStartHour: 0, timeZone: 北京)

    // 立一门课不该当场欠一天账。诵经从明天算起。
    #expect(后.requiredItemIDs == [念佛.id])
}

@Test @MainActor func 没有迟到项时一条快照都不多写() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    ctx.insert(念佛)

    _ = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    for _ in 0..<5 {
        _ = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    }

    // 另开一个上下文问「盘上到底有几条」——同一个 context 会把待写的也算进来。
    let 独立 = ModelContext(try ModelContainerFactory.inMemory())
    _ = 独立
    let 全部 = try ctx.fetch(FetchDescriptor<DaySnapshot>())
    #expect(全部.count == 1)
}

@Test @MainActor func 追加过一次就不会再追加() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    let 打坐 = 课("打坐", 立于: 时刻(7, 22, 9))
    ctx.insert(念佛); ctx.insert(打坐)

    _ = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    _ = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)
    _ = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)

    // 初次一条 + 追加一条 = 两条。第三次调用不该再添。
    #expect(try ctx.fetch(FetchDescriptor<DaySnapshot>()).count == 2)
}

@Test @MainActor func 已归档的迟到定课不会被追加() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    let 旧课 = 课("旧课", 立于: 时刻(7, 1, 9), 归档: true)
    ctx.insert(念佛); ctx.insert(旧课)

    _ = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 旧课], dayStartHour: 0, timeZone: 北京)
    #expect(后.requiredItemIDs == [念佛.id])
}

@Test @MainActor func 追加项的目标取自追加时那条快照() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9), 目标: 1000)
    let 打坐 = 课("打坐", 立于: 时刻(7, 22, 9), 目标: 30)
    ctx.insert(念佛); ctx.insert(打坐)

    _ = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)

    // 最早那条快照对打坐毫无意见，故取「含它的最早一条」——就是追加的这条。
    #expect(后.goals[打坐.id.uuidString] == 30)
    #expect(后.goals[念佛.id.uuidString] == 1000)
}

@Test @MainActor func 初次定格仍旧收下全部在册定课() throws {
    let (ledger, ctx) = try 建()
    // 用户今天装了 App，今天立的课，补记三天前。
    let 念佛 = 课("念佛", 立于: 时刻(7, 28, 10))
    ctx.insert(念佛)

    let 计划 = try ledger.plan(for: 20260725, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)

    // **createdAt 判据只管追加，绝不能套到初次定格上。**
    // 套上去的话，新用户补录过去三十天会得到三十条空快照，
    // 每一天都记着几百声却显示「无课」——正是 §5.6 要治的那个病，反倒被治法造出来。
    #expect(计划.requiredItemIDs == [念佛.id])
}

@Test @MainActor func 空快照的一天在定课同步进来后能自愈() throws {
    let (ledger, ctx) = try 建()
    // 换新机首启：一条定课都还没推下来。
    let 空 = try ledger.plan(for: 20260728, activeItems: [], dayStartHour: 0, timeZone: 北京)
    #expect(空.requiredItemIDs.isEmpty)

    let 全 = (1...3).map { 课("第\($0)门", 立于: 时刻(7, 10, 9)) }
    for it in 全 { ctx.insert(it) }

    let 愈 = try ledger.plan(for: 20260728, activeItems: 全, dayStartHour: 0, timeZone: 北京)
    #expect(愈.requiredItemIDs.count == 3)
}
