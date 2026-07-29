import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeItemStore() throws -> (PracticeItemStore, DayLedger, ModelContext) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    return (PracticeItemStore(context: ctx), DayLedger(context: ctx, deviceName: "iPhone·TEST"), ctx)
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
@Test func 新建定课默认不设目标() throws {
    let (store, _, _) = try makeItemStore()
    let item = try store.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: nil, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    #expect(item.dailyGoal == nil, "不设目标必须能表达——九款竞品无一预设数字")
    #expect(try store.activeItems().count == 1)
}

@MainActor
@Test func 从模板新建带上templateKey与量词() throws {
    let (store, _, _) = try makeItemStore()
    let mantra = TemplateCatalog.template(key: "mantra")!
    let item = try store.create(from: mantra)
    #expect(item.templateKey == "mantra")
    #expect(item.name == "持咒")
    #expect(item.unit == "遍")
    #expect(item.measureType == .count)
    #expect(item.dailyGoal == nil)
}

@MainActor
@Test func 新建的排到末尾() throws {
    let (store, _, _) = try makeItemStore()
    let a = try store.create(from: TemplateCatalog.template(key: "chanting")!)
    let b = try store.create(from: TemplateCatalog.template(key: "mantra")!)
    let c = try store.create(from: TemplateCatalog.template(key: "sutra")!)
    #expect([a.sortOrder, b.sortOrder, c.sortOrder] as [Int] == [0, 1, 2])
    #expect(try store.activeItems().map(\.name) == ["念佛", "持咒", "诵经"])
}

@MainActor
@Test func 新建排序时把已归档的也算进去() throws {
    // 否则归档一项再新建，新项会和某个已归档项抢同一个 sortOrder，
    // 用户把归档项恢复回来时两者顺序就成了掷骰子。
    let (store, _, _) = try makeItemStore()
    let a = try store.create(from: TemplateCatalog.template(key: "chanting")!)
    let b = try store.create(from: TemplateCatalog.template(key: "mantra")!)
    try store.archive(b)
    let c = try store.create(from: TemplateCatalog.template(key: "sutra")!)
    #expect(c.sortOrder == 2, "应当续在已归档项之后，实际 \(c.sortOrder)")
    #expect(a.sortOrder != c.sortOrder)
}

@MainActor
@Test func 归档后不再出现在活跃清单但历史流水一分不少() throws {
    // 这是整个数据模型的立身之本：只归档不硬删。
    let (store, ledger, _) = try makeItemStore()
    let item = try store.create(from: TemplateCatalog.template(key: "chanting")!)
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 1000, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)

    try store.archive(item)

    #expect(try store.activeItems().isEmpty)
    #expect(try store.archivedItems().count == 1)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 1000, "归档不该动到历史流水")
    #expect(try store.item(id: item.id)?.name == "念佛", "按 id 仍应能取回")
}

@MainActor
@Test func 可以把归档的恢复回来() throws {
    let (store, _, _) = try makeItemStore()
    let item = try store.create(from: TemplateCatalog.template(key: "chanting")!)
    try store.archive(item)
    try store.unarchive(item)
    #expect(try store.activeItems().count == 1)
    #expect(try store.archivedItems().isEmpty)
}

@MainActor
@Test func 改目标不影响历史圆满判定() throws {
    // §6.6 要求这一点在 UI 上明示，但首先得在代码上成立。
    // 过去每天的目标定格在 DaySnapshot 里，改当前配置不该动它。
    let (store, ledger, _) = try makeItemStore()
    let item = try store.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: 1000, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    let 昨天 = 20260727
    let plan = try ledger.plan(for: 昨天, activeItems: [item])
    let now = 北京(7, 27, 9, 0)
    try ledger.record(item: item, amount: 1000, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间, onDay: 昨天)
    #expect(try ledger.fulfillment(of: item.id, plan: plan) == .fulfilled, "前提：昨天已圆满")

    try store.update(item, name: "念佛", measureType: .count, unit: "声",
                     dailyGoal: 3000, iconName: "circle.grid.3x3",
                     colorHex: Palette.Light.fulfilled)

    let 重读 = try ledger.existingPlan(for: 昨天)!
    #expect(try ledger.fulfillment(of: item.id, plan: 重读) == .fulfilled,
            "把目标从 1000 改到 3000，昨天的圆满不能因此变回未完成——那等于告诉他昨天白做了")
}

@MainActor
@Test func 改动会更新updatedAt() throws {
    let (store, _, _) = try makeItemStore()
    let 建于 = 北京(7, 1, 8, 0)
    let item = try store.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: nil, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled, at: 建于)
    #expect(item.updatedAt == 建于)
    let 改于 = 北京(7, 28, 20, 0)
    try store.update(item, name: "念阿弥陀佛", measureType: .count, unit: "声",
                     dailyGoal: 108, iconName: "circle.grid.3x3",
                     colorHex: Palette.Light.fulfilled, at: 改于)
    #expect(item.name == "念阿弥陀佛")
    #expect(item.dailyGoal == 108)
    #expect(item.updatedAt == 改于)
    #expect(item.createdAt == 建于, "改动不该动 createdAt")
}

@MainActor
@Test func 拖拽排序按传入顺序重排() throws {
    let (store, _, _) = try makeItemStore()
    let a = try store.create(from: TemplateCatalog.template(key: "chanting")!)
    let b = try store.create(from: TemplateCatalog.template(key: "mantra")!)
    let c = try store.create(from: TemplateCatalog.template(key: "sutra")!)
    try store.reorder([c, a, b])
    #expect(try store.activeItems().map(\.name) == ["诵经", "念佛", "持咒"])
    #expect([c.sortOrder, a.sortOrder, b.sortOrder] as [Int] == [0, 1, 2])
}

@MainActor
@Test func 排序相同时按创建时间兜底不掷骰子() throws {
    let (store, _, ctx) = try makeItemStore()
    let a = PracticeItem(name: "先建的", sortOrder: 0, createdAt: 北京(7, 1, 8, 0))
    let b = PracticeItem(name: "后建的", sortOrder: 0, createdAt: 北京(7, 2, 8, 0))
    ctx.insert(b); ctx.insert(a)
    try ctx.save()
    #expect(try store.activeItems().map(\.name) == ["先建的", "后建的"])
}
