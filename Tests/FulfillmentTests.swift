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

    let snap = try ledger.plan(for: 20260728, activeItems: [a, b], dayStartHour: 0, timeZone: 北京时间)
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

    _ = try ledger.plan(for: 20260728, activeItems: [a], dayStartHour: 0, timeZone: 北京时间)

    a.dailyGoal = 3000
    try ctx.save()

    let again = try ledger.plan(for: 20260728, activeItems: [a], dayStartHour: 0, timeZone: 北京时间)
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

    let snap = try ledger.plan(for: 20260728, activeItems: [a], dayStartHour: 0, timeZone: 北京时间)
    #expect(snap.goals[a.id.uuidString] == 1000, "去重必须确定性地取最早那条")
}

@MainActor
@Test func 同日多条快照的应做项取并集() throws {
    // 场景：iPad 清早只登记了 a，iPhone 稍后新增并修了 b。
    // 若只取最早一条，b 会被判为当日无需完成而从清单上消失。
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    let b = PracticeItem(name: "打坐", measureType: .duration, dailyGoal: 1800)
    ctx.insert(a); ctx.insert(b)
    let early = DaySnapshot(dayKey: 20260728, requiredItemIDs: [a.id],
                            goals: [a.id.uuidString: 1000],
                            createdAt: Date(timeIntervalSince1970: 1000))
    let late = DaySnapshot(dayKey: 20260728, requiredItemIDs: [a.id, b.id],
                           goals: [a.id.uuidString: 9999, b.id.uuidString: 1800],
                           createdAt: Date(timeIntervalSince1970: 2000))
    ctx.insert(late); ctx.insert(early)
    try ctx.save()

    let snap = try ledger.plan(for: 20260728, activeItems: [a, b], dayStartHour: 0, timeZone: 北京时间)
    #expect(Set(snap.requiredItemIDs) == [a.id, b.id], "应做项应取并集，b 不能丢")
    #expect(snap.goals[a.id.uuidString] == 1000, "a 已在最早快照，最早目标为准")
}

@MainActor
@Test func 并集中新增项沿用其来源快照的目标() throws {
    // b 只存在于较晚那条快照，最早快照对它没有任何意见，
    // 故 b 的目标取自「含它的最早一条快照」。
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    let b = PracticeItem(name: "打坐", measureType: .duration, dailyGoal: 1800)
    ctx.insert(a); ctx.insert(b)
    let early = DaySnapshot(dayKey: 20260728, requiredItemIDs: [a.id],
                            goals: [a.id.uuidString: 1000],
                            createdAt: Date(timeIntervalSince1970: 1000))
    let late = DaySnapshot(dayKey: 20260728, requiredItemIDs: [a.id, b.id],
                           goals: [a.id.uuidString: 9999, b.id.uuidString: 1800],
                           createdAt: Date(timeIntervalSince1970: 2000))
    ctx.insert(late); ctx.insert(early)
    try ctx.save()

    let snap = try ledger.plan(for: 20260728, activeItems: [a, b], dayStartHour: 0, timeZone: 北京时间)
    #expect(snap.goals[b.id.uuidString] == 1800, "并集新增项沿用其来源快照的目标")
}

@MainActor
@Test func 并集严格按uuidString升序而非到达次序() throws {
    // 两台设备收到同一组 DaySnapshot，无论到达次序、无论 Set 迭代次序，
    // 都必须产出**逐位相同**的 requiredItemIDs，否则「跨设备一致」只是口号。
    //
    // 用显式 UUID 钉死期望，并刻意打乱各项在快照里的出现次序（既非升序也非插入序）：
    // 若并集按到达/Set 迭代次序拼接，几乎不可能恰好排成升序；
    // 唯有真正按 uuidString 排序才得到 [u1…u6]。故断言与「排序后的期望」**逐位相等**——
    // 不是集合相等，也不是「两次运行彼此相等」：后两者对任何确定性算法（含完全不排序）恒真，
    // 根本约束不住排序。多用几个 UUID 是为了让「删掉 .sorted」几乎必然被逮到（1/6! 才会侥幸蒙混）。
    let u1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let u2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let u3 = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    let u4 = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    let u5 = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    let u6 = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    let 期望 = [u1, u2, u3, u4, u5, u6]

    func merged(insertLateFirst: Bool) throws -> [UUID] {
        let container = try ModelContainerFactory.inMemory()
        let ctx = ModelContext(container)
        let ledger = DayLedger(context: ctx, deviceName: "iPhone·TEST")
        // 各项在快照里刻意乱序出现（靠后的先登场），自然累加序 u6,u3,u1,u5,u2,u4 ≠ 升序。
        let early = DaySnapshot(dayKey: 20260728, requiredItemIDs: [u6, u3, u1],
                                goals: [:],
                                createdAt: Date(timeIntervalSince1970: 1000))
        let late = DaySnapshot(dayKey: 20260728, requiredItemIDs: [u5, u2, u4, u6],
                               goals: [:],
                               createdAt: Date(timeIntervalSince1970: 2000))
        if insertLateFirst { ctx.insert(late); ctx.insert(early) }
        else { ctx.insert(early); ctx.insert(late) }
        try ctx.save()
        return try #require(try ledger.existingPlan(for: 20260728)).requiredItemIDs
    }

    // 核心断言：结果必须严格等于 uuidString 升序数组；到达/迭代次序不得泄漏进来。
    #expect(try merged(insertLateFirst: true) == 期望,
            "并集必须严格按 uuidString 升序，删掉 .sorted 即会泄漏 Set/到达次序")
    // 附加：到达次序无关（保留原意，但不再是唯一断言）。
    #expect(try merged(insertLateFirst: false) == 期望,
            "颠倒插入次序也必须得到同一逐位相同的数组")
}

@MainActor
@Test func 读取计划不改写任何源快照() throws {
    // 合并是派生视图、绝不回写：读取后每条源快照都必须还是当初被创建时的原样
    // （不只是「记录还在」，而是 requiredItemIDs 与 goals 一字未改）。
    // 只要源快照原封不动，即便某条在 LWW 里输掉，下次读取仍能从幸存的重算并自愈。
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    let b = PracticeItem(name: "打坐", measureType: .duration, dailyGoal: 1800)
    ctx.insert(a); ctx.insert(b)
    let early = DaySnapshot(dayKey: 20260728, requiredItemIDs: [a.id],
                            goals: [a.id.uuidString: 1000],
                            createdAt: Date(timeIntervalSince1970: 1000))
    let late = DaySnapshot(dayKey: 20260728, requiredItemIDs: [a.id, b.id],
                           goals: [b.id.uuidString: 1800],
                           createdAt: Date(timeIntervalSince1970: 2000))
    ctx.insert(late); ctx.insert(early)
    try ctx.save()

    _ = try ledger.plan(for: 20260728, activeItems: [a, b], dayStartHour: 0, timeZone: 北京时间)

    let key = 20260728
    let remaining = try ctx.fetch(
        FetchDescriptor<DaySnapshot>(predicate: #Predicate { $0.dayKey == key })
    )
    #expect(remaining.count == 2, "合并绝不删除任何源快照，否则自愈能力尽失")

    let savedEarly = try #require(remaining.first { $0.id == early.id })
    #expect(savedEarly.requiredItemIDs == [a.id], "源快照被回写了，读路径不该写库")
    #expect(savedEarly.goals == [a.id.uuidString: 1000], "源快照的目标被回写了")

    let savedLate = try #require(remaining.first { $0.id == late.id })
    #expect(savedLate.requiredItemIDs == [a.id, b.id], "源快照被回写了，读路径不该写库")
    #expect(savedLate.goals == [b.id.uuidString: 1800], "源快照的目标被回写了")
}

@MainActor
@Test func 只读查询过去的日子不写入任何东西() throws {
    // Finding 1 回归：月历翻看历史只该渲染，绝不能凭空捏造一条过去的快照，
    // 断言用户当时「本该」做今年才新建的功课——那种伪造会同步到每台设备、永久留存。
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()

    let plan = try ledger.existingPlan(for: 20250115)
    #expect(plan == nil, "该日无快照，只读查询必须返回 nil 而非凭空生成")
    #expect(try ctx.fetch(FetchDescriptor<DaySnapshot>()).count == 0,
            "只读查询过去的日子绝不许写入任何快照")
}

@MainActor
@Test func 排除已归档的定课项() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛")
    let old = PracticeItem(name: "旧功课", isArchived: true)
    ctx.insert(a); ctx.insert(old)
    try ctx.save()

    let snap = try ledger.plan(for: 20260728, activeItems: [a, old], dayStartHour: 0, timeZone: 北京时间)
    #expect(snap.requiredItemIDs == [a.id])
}

@MainActor
@Test func 未达目标为待完成() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.plan(for: 20260728, activeItems: [a], dayStartHour: 0, timeZone: 北京时间)

    let now = 北京(7, 28, 9)
    try ledger.record(item: a, amount: 500, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.fulfillment(of: a.id, plan: snap) == .pending)
}

@MainActor
@Test func 达到目标为圆满() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.plan(for: 20260728, activeItems: [a], dayStartHour: 0, timeZone: 北京时间)

    let now = 北京(7, 28, 9)
    try ledger.record(item: a, amount: 1000, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.fulfillment(of: a.id, plan: snap) == .fulfilled)
}

@MainActor
@Test func 未设目标时做了就圆满() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "放生", measureType: .check, dailyGoal: nil)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.plan(for: 20260728, activeItems: [a], dayStartHour: 0, timeZone: 北京时间)

    #expect(try ledger.fulfillment(of: a.id, plan: snap) == .pending)

    let now = 北京(7, 28, 9)
    try ledger.record(item: a, amount: 1, source: .manual,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    #expect(try ledger.fulfillment(of: a.id, plan: snap) == .fulfilled)
}

@MainActor
@Test func 当日不需做的项为无需完成() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛")
    let b = PracticeItem(name: "诵经")
    ctx.insert(a); ctx.insert(b)
    try ctx.save()
    // 只把 a 列入当日清单
    let snap = try ledger.plan(for: 20260728, activeItems: [a], dayStartHour: 0, timeZone: 北京时间)

    #expect(try ledger.fulfillment(of: b.id, plan: snap) == .notRequired)
}

@MainActor
@Test func 撤销后从圆满退回待完成() throws {
    let (ledger, ctx) = try makeEnv()
    let a = PracticeItem(name: "念佛", dailyGoal: 1000)
    ctx.insert(a)
    try ctx.save()
    let snap = try ledger.plan(for: 20260728, activeItems: [a], dayStartHour: 0, timeZone: 北京时间)

    let now = 北京(7, 28, 9)
    let s = try ledger.record(item: a, amount: 1000, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    #expect(try ledger.fulfillment(of: a.id, plan: snap) == .fulfilled)

    try ledger.revoke(s, at: now, timeZone: 北京时间)
    #expect(try ledger.fulfillment(of: a.id, plan: snap) == .pending)
}
