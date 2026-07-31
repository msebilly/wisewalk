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
    let (store, _, ctx) = try makeItemStore()
    let a = try store.create(from: TemplateCatalog.template(key: "chanting")!)
    let b = try store.create(from: TemplateCatalog.template(key: "mantra")!)
    let c = try store.create(from: TemplateCatalog.template(key: "sutra")!)
    // `as [Int]` 不是多余的：`#expect` 把 `==` 展开成泛型的 `__checkBinaryOperation`，
    // 而这里 `==` 两边都是数组字面量，`IndexSet` 与 `IndexPath` 同样
    // `ExpressibleByArrayLiteral<Int>`，泛型参数在三者之间歧义，编译不过。
    #expect([a.sortOrder, b.sortOrder, c.sortOrder] as [Int] == [0, 1, 2])
    #expect(try store.activeItems().map(\.name) == ["念佛", "持咒", "诵经"])
    #expect(!ctx.hasChanges, "create 之后不该还有没落盘的改动")
}

@MainActor
@Test func 新建排序时把已归档的也算进去() throws {
    // 否则归档一项再新建，新项会和某个已归档项抢同一个 sortOrder，
    // 用户把归档项恢复回来时两者顺序就成了掷骰子。
    //
    // 归档项的 sortOrder 特意留出空档（0 之后直接跳到 5）：连续排布下
    // 「取最大值 +1」与「数个数」得数相同，测不出二者之别，
    // 而后者正是这条测试要挡住的写法。
    let (store, _, ctx) = try makeItemStore()
    let a = try store.create(from: TemplateCatalog.template(key: "chanting")!)
    ctx.insert(PracticeItem(name: "早就归档的", sortOrder: 5, isArchived: true,
                            createdAt: 北京(7, 1, 8, 0)))
    try ctx.save()
    let c = try store.create(from: TemplateCatalog.template(key: "sutra")!)
    #expect(c.sortOrder == 6, "应当续在已归档项之后，实际 \(c.sortOrder)")
    #expect(a.sortOrder != c.sortOrder)
}

@MainActor
@Test func 记过功课的定课改不了量法() throws {
    // 立身之本：已经记下的功课不许被事后重新解释。
    // amount 是个裸 Int，不记自己的单位——打坐每笔 1800 秒，
    // 量法一改成计数就当场变成「1800 遍」，用户从没念过的数字。
    let (store, ledger, ctx) = try makeItemStore()
    let item = try store.create(from: TemplateCatalog.template(key: "meditation")!)
    let now = 北京(7, 28, 6, 0)
    try ledger.record(item: item, amount: 1800, source: .timer,
                      startedAt: 北京(7, 28, 5, 30), at: now, timeZone: 北京时间)

    // 每个字段都传与现值不同的值：逐字段断言才有意义。
    #expect(throws: PracticeItemStoreError.measureTypeLockedByHistory) {
        try store.update(item, name: "打坐（改）", measureType: .count, unit: "遍",
                         dailyGoal: 3000, iconName: "star", colorHex: "#123456", at: now)
    }
    // 掷错之后一个字段都不许动过——不能改了一半才发现不让改。
    // 逐字段断言只钉得住「守卫在这几个赋值之前」；`!ctx.hasChanges` 钉的是
    // 「守卫在**所有**赋值之前」，把守卫往下挪哪怕一行都会红。
    #expect(item.measureType == .duration)
    #expect(item.name == "打坐")
    #expect(item.unit == "")
    #expect(item.dailyGoal == nil)
    #expect(!ctx.hasChanges, "掷错之后不该留下任何没落盘的改动")
}

@MainActor
@Test func 没记过功课的定课可以改量法() throws {
    // 刚建错了量法还没记过，本来就该让人改回来。
    //
    // 库里**另有**一项记满了流水，这不是布景：`hasAnyHistory` 的谓词
    // 穿透可选关系（`$0.item?.id == itemID`），而 `DayLedger.sessions(on:itemID:)`
    // 的注释里写明这种形状「在 SwiftData 上行为不稳」并刻意改走内存过滤。
    // 谓词一旦失准，把念佛的流水算到打坐头上，这条就红。
    // 少了这第二项，把谓词整个删成 `FetchDescriptor<PracticeSession>()` 都测不出来。
    let (store, ledger, _) = try makeItemStore()
    let chanting = try store.create(from: TemplateCatalog.template(key: "chanting")!)
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: chanting, amount: 1000, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)

    let meditation = try store.create(from: TemplateCatalog.template(key: "meditation")!)
    try store.update(meditation, name: "打坐", measureType: .count, unit: "坐",
                     dailyGoal: nil, iconName: meditation.iconName,
                     colorHex: meditation.colorHex, at: now)
    #expect(meditation.measureType == .count)
    #expect(meditation.unit == "坐")
}

@MainActor
@Test func 有历史也照样能改名换色只是量法照旧() throws {
    // 锁的只是量法这一个字段，别把整个编辑页一起锁死了。
    let (store, ledger, _) = try makeItemStore()
    let item = try store.create(from: TemplateCatalog.template(key: "chanting")!)
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 1000, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)
    try store.update(item, name: "念佛（改）", measureType: .count, unit: "声",
                     dailyGoal: 3000, iconName: "star", colorHex: "#123456", at: now)
    #expect(item.name == "念佛（改）")
    #expect(item.dailyGoal == 3000)
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
    let plan = try ledger.plan(for: 昨天, activeItems: [item], dayStartHour: 0, timeZone: 北京时间)
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
    let (store, _, ctx) = try makeItemStore()
    let a = try store.create(from: TemplateCatalog.template(key: "chanting")!)
    let b = try store.create(from: TemplateCatalog.template(key: "mantra")!)
    let c = try store.create(from: TemplateCatalog.template(key: "sutra")!)
    try store.reorder([c, a, b])
    #expect(try store.activeItems().map(\.name) == ["诵经", "念佛", "持咒"])
    #expect([c.sortOrder, a.sortOrder, b.sortOrder] as [Int] == [0, 1, 2])
    // 钉住那句 save()。少了它，本文件其余断言一条都不会红：
    // makeItemStore 只发一个 ModelContext，而 FetchDescriptor 的
    // includePendingChanges 默认为 true，未落盘的改动照样查得到。
    #expect(!ctx.hasChanges, "reorder 之后不该还有没落盘的改动")
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
