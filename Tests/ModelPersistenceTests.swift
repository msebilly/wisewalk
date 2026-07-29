import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@Test func 定课项与流水可以往返() throws {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)

    let item = PracticeItem(
        name: "念佛",
        iconName: "circle.hexagonpath",
        measureType: .count,
        unit: "声",
        dailyGoal: 1000,
        scheduleRule: .daily,
        reminderTimes: [360, 1290],
        templateKey: "nianfo"
    )
    ctx.insert(item)

    let session = PracticeSession(
        item: item,
        dayKey: 20260728,
        tzOffsetMinutes: 480,
        amount: 108,
        startedAt: Date(timeIntervalSince1970: 1_785_000_000),
        endedAt: Date(timeIntervalSince1970: 1_785_000_600),
        source: .counter,
        deviceName: "iPhone·A1"
    )
    ctx.insert(session)
    try ctx.save()

    let items = try ctx.fetch(FetchDescriptor<PracticeItem>())
    #expect(items.count == 1)
    #expect(items[0].name == "念佛")
    #expect(items[0].measureType == .count)
    #expect(items[0].scheduleRule == .daily)
    #expect(items[0].reminderTimes == [360, 1290])
    #expect(items[0].dailyGoal == 1000)
    #expect(items[0].sessions?.count == 1)

    let sessions = try ctx.fetch(FetchDescriptor<PracticeSession>())
    #expect(sessions.count == 1)
    #expect(sessions[0].amount == 108)
    #expect(sessions[0].source == .counter)
    #expect(sessions[0].tzOffsetMinutes == 480)
    #expect(sessions[0].item?.id == item.id)
}

@Test func 不设目标的定课项可以往返() throws {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)
    let item = PracticeItem(name: "打坐", measureType: .duration, dailyGoal: nil)
    ctx.insert(item)
    try ctx.save()

    let got = try ctx.fetch(FetchDescriptor<PracticeItem>())
    #expect(got[0].dailyGoal == nil)
    #expect(got[0].measureType == .duration)
}

@Test func 快照可以往返() throws {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)
    let a = UUID(), b = UUID()
    let snap = DaySnapshot(
        dayKey: 20260728,
        requiredItemIDs: [a, b],
        goals: [a.uuidString: 1000]
    )
    ctx.insert(snap)
    try ctx.save()

    let got = try ctx.fetch(FetchDescriptor<DaySnapshot>())
    #expect(got.count == 1)
    #expect(Set(got[0].requiredItemIDs) == [a, b])
    #expect(got[0].goals[a.uuidString] == 1000)
    #expect(got[0].goals[b.uuidString] == nil)
}

@Test func 清理定课项后流水仍然保留() throws {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)
    let item = PracticeItem(name: "持咒")
    ctx.insert(item)
    let s = PracticeSession(
        item: item, dayKey: 20260728, tzOffsetMinutes: 480, amount: 21,
        startedAt: Date(), source: .counter, deviceName: "t"
    )
    ctx.insert(s)
    try ctx.save()

    ctx.delete(item)
    try ctx.save()

    let sessions = try ctx.fetch(FetchDescriptor<PracticeSession>())
    #expect(sessions.count == 1, "deleteRule .nullify 必须保住流水")
    #expect(sessions[0].amount == 21)
    #expect(sessions[0].item == nil)
}
