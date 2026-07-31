import Testing
import SwiftData
import Foundation
@testable import WiseWalk

private let 北京时间 = TimeZone(identifier: "Asia/Shanghai")!

private func 北京(_ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = 北京时间
    return cal.date(from: c)!
}

@MainActor
private func makeEditorEnv() throws -> (PracticeItemStore, DayLedger) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    return (PracticeItemStore(context: ctx), DayLedger(context: ctx, deviceName: "iPhone·TEST"))
}

@MainActor
@Test func 从模板新建带出名称量法与量词() throws {
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.apply(template: TemplateCatalog.template(key: "mantra")!)
    #expect(vm.name == "持咒")
    #expect(vm.measureType == .count)
    #expect(vm.unit == "遍")
    #expect(vm.dailyGoal == nil, "模板不预置目标值——九款竞品无一预设数字")
}

@MainActor
@Test func 空白新建也能存支持自定义名称() throws {
    // §6.6：自定义经咒名称是竞品高频诉求。
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.name = "楞严咒"
    vm.measureType = .count
    vm.unit = "遍"
    #expect(vm.canSave)
    let item = try vm.save()
    #expect(item.name == "楞严咒")
    #expect(try items.activeItems().map(\.name) == ["楞严咒"])
}

@MainActor
@Test func 名称为空或只有空格不给存() throws {
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.name = ""
    #expect(!vm.canSave)
    vm.name = "   "
    #expect(!vm.canSave)
    #expect(throws: ItemEditorError.emptyName) { _ = try vm.save() }
}

@MainActor
@Test func 名称两端空格会被去掉() throws {
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.name = "  大悲咒 "
    let item = try vm.save()
    #expect(item.name == "大悲咒")
}

@MainActor
@Test func 编辑已有项时字段先填好() throws {
    let (items, _) = try makeEditorEnv()
    let item = try items.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: 1080, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    let vm = ItemEditorViewModel(store: items, editing: item)
    #expect(vm.name == "念佛")
    #expect(vm.unit == "声")
    #expect(vm.dailyGoal == 1080)
    #expect(vm.iconName == "circle.grid.3x3")
}

@MainActor
@Test func 保存编辑是改原项不是新建一项() throws {
    let (items, _) = try makeEditorEnv()
    let item = try items.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: 1080, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    let vm = ItemEditorViewModel(store: items, editing: item)
    vm.dailyGoal = 3000
    let saved = try vm.save()
    #expect(saved.id == item.id, "改目标不该造出第二个「念佛」")
    #expect(try items.activeItems().count == 1)
    #expect(item.dailyGoal == 3000)
}

@MainActor
@Test func 记过功课时量法选择器先锁上() throws {
    // 不能等用户改完点保存才掷错——那时他已经改了半张表单。
    let (items, ledger) = try makeEditorEnv()
    let item = try items.create(name: "打坐", measureType: .duration, unit: "",
                                dailyGoal: 1800, iconName: "figure.mind.and.body",
                                colorHex: Palette.Light.fulfilled)
    let now = 北京(7, 28, 6, 0)
    try ledger.record(item: item, amount: 1800, source: .timer,
                      startedAt: 北京(7, 28, 5, 30), at: now, timeZone: 北京时间)
    let vm = ItemEditorViewModel(store: items, editing: item)
    #expect(vm.isMeasureTypeLocked)
}

@MainActor
@Test func 没记过功课与新建时量法都能改() throws {
    let (items, _) = try makeEditorEnv()
    let item = try items.create(name: "打坐", measureType: .duration, unit: "",
                                dailyGoal: 1800, iconName: "figure.mind.and.body",
                                colorHex: Palette.Light.fulfilled)
    #expect(!ItemEditorViewModel(store: items, editing: item).isMeasureTypeLocked)
    #expect(!ItemEditorViewModel(store: items).isMeasureTypeLocked, "新建时无历史可言")
}

@MainActor
@Test func 改目标不改历史圆满() throws {
    // spec §6.6 点名要求「须在 UI 上明示」，那前提是它真的成立。这条测试锁住它。
    let (items, ledger) = try makeEditorEnv()
    let item = try items.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: 1000, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    let plan = try ledger.plan(for: 20260701, activeItems: [item], dayStartHour: 0, timeZone: 北京时间)
    let now = Date()
    try ledger.record(item: item, amount: 1000, source: .counter,
                      startedAt: now, at: now, onDay: 20260701)
    #expect(try ledger.fulfillment(of: item.id, plan: plan) == .fulfilled)

    let vm = ItemEditorViewModel(store: items, editing: item)
    vm.dailyGoal = 100_000
    _ = try vm.save()

    let 重读 = try ledger.existingPlan(for: 20260701)!
    #expect(try ledger.fulfillment(of: item.id, plan: 重读) == .fulfilled,
            "7 月 1 日已经圆满过，改今天的目标不该把它变回未完成")
}

@MainActor
@Test func 计时类与勾选类不需要量词() throws {
    // 「打坐 30 遍」是荒唐的。切到计时或勾选就把量词清空。
    // **两种都要验**：实现写成 `if measureType == .duration` 时勾选类会漏网，
    // 而这条测试的名字里明写着「与勾选类」。
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.name = "打坐"
    vm.unit = "遍"
    vm.measureType = .duration
    #expect(vm.unit == "")
    let item = try vm.save()
    #expect(item.unit == "")

    let vm2 = ItemEditorViewModel(store: items)
    vm2.name = "放生"
    vm2.unit = "次"
    vm2.measureType = .check
    #expect(vm2.unit == "", "勾选类同样不该带量词")
    #expect(try vm2.save().unit == "")
}

@MainActor
@Test func 换量法时目标值也一并清掉() throws {
    // ⛔ `dailyGoal` 计数类存遍数、计时类存**秒**，两套单位之间没有任何
    // 有意义的换算。不清的话：计数类下设目标 30（遍），改成计时类，
    // `dailyGoal` 仍是 30——而计时类按秒读，于是**「打坐 30 秒」就算圆满**。
    //
    // 圆满是这个 App 唯一一处替用户下的判断，不许它凭一次量法切换就变成假的。
    // 与量词同一条理由：换不过去的东西就别硬留着，请用户重设。
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.name = "打坐"
    vm.goalDisplay = 30
    #expect(vm.dailyGoal == 30, "计数类下 30 就是 30 遍")

    vm.measureType = .duration
    #expect(vm.dailyGoal == nil, "30 遍换不成任何有意义的时长")
    #expect(vm.goalDisplay == nil)
    #expect(try vm.save().dailyGoal == nil, "落库的也得是「不设目标」，不是 30 秒")
}

@MainActor
@Test func 切回计数类时量词不自动冒出来() throws {
    // 自动填一个用户没选过的量词，比留空更让人困惑。
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.measureType = .duration
    vm.measureType = .count
    #expect(vm.unit == "")
}

@MainActor
@Test func 目标值非正一律当作不设目标() throws {
    // 「目标 0 声」和「不设目标」在圆满判定上是两回事，
    // 但用户想表达的只有后者——LedgerMath 对 nil 与 0 的处理必须一致地落到「做了就算」。
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.name = "念佛"
    vm.dailyGoal = 0
    let a = try vm.save()
    #expect(a.dailyGoal == nil)

    let vm2 = ItemEditorViewModel(store: items)
    vm2.name = "持咒"
    vm2.dailyGoal = -5
    #expect(try vm2.save().dailyGoal == nil)
}

@MainActor
@Test func 计时类界面填分钟落库存秒() throws {
    // 没人愿意在「每日目标」里填 1800。换算只在 goalDisplay 这一层做一次。
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.name = "打坐"
    vm.measureType = .duration
    vm.goalDisplay = 30
    #expect(vm.dailyGoal == 1800)
    #expect(vm.goalDisplay == 30)
    #expect(try vm.save().dailyGoal == 1800)
}

@MainActor
@Test func 计数类界面与落库同一个数() throws {
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.name = "念佛"
    vm.measureType = .count
    vm.goalDisplay = 1080
    #expect(vm.dailyGoal == 1080)
    #expect(vm.goalDisplay == 1080)
}

@MainActor
@Test func 快捷档随量法切换() throws {
    // 给打坐列「108 分」「1080 分」是荒唐的；给念佛列「15 遍」也一样。
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    #expect(vm.goalChips == TemplateCatalog.goalChips)
    vm.measureType = .duration
    #expect(vm.goalChips == TemplateCatalog.durationGoalChips)
    #expect(vm.goalChips.first == Int?.none, "「不设目标」永远排在最前且是默认")
}

@MainActor
@Test func 编辑计时类时目标先换算成分钟填好() throws {
    let (items, _) = try makeEditorEnv()
    let item = try items.create(name: "打坐", measureType: .duration, unit: "",
                                dailyGoal: 1800, iconName: "figure.mind.and.body",
                                colorHex: Palette.Light.accent)
    let vm = ItemEditorViewModel(store: items, editing: item)
    #expect(vm.measureType == .duration)
    #expect(vm.dailyGoal == 1800)
    #expect(vm.goalDisplay == 30, "界面上该显示 30 分，不是 1800")
}

@MainActor
@Test func 新建项排在最后() throws {
    let (items, _) = try makeEditorEnv()
    for n in ["念佛", "持咒", "拜佛"] {
        let vm = ItemEditorViewModel(store: items)
        vm.name = n
        _ = try vm.save()
    }
    #expect(try items.activeItems().map(\.name) == ["念佛", "持咒", "拜佛"])
}

@MainActor
@Test func 图标与颜色都从预置里挑() throws {
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    #expect(TemplateCatalog.colorChoices.contains(vm.colorHex), "默认色必须在色板里")
    // 只验非空太弱：SF Symbol 名字写错不会报错，只渲染成一片空白，
    // 而「非空」对一个写错的名字照样成立。名字里说的是「从预置里挑」，就验这个。
    #expect(TemplateCatalog.iconChoices.contains(vm.iconName), "默认图标必须在候选里")
}

@MainActor
@Test func 打勾类不给每日目标() throws {
    // ⛔ 打勾类一天最多记 1，而 `LedgerMath.isFulfilled` 算的是 `total >= goal`。
    // 给它设「每日目标 108」就是 `1 >= 108`——**用户天天打勾、天天不圆满**，
    // 而且找不出原因：他不会想到是那个自己随手点过的目标数。
    //
    // 初版 `goalChips` 把计数类那一套（[nil, 108, 1080]）原样给了打勾类，
    // 于是「每日目标」连同 108、1080 两个档明晃晃摆在早晚课的表单上。
    // 圆满是这个 App 唯一一处替用户下的判断，不许它被一次随手点击永久夺走。
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.name = "早课"
    vm.measureType = .check
    #expect(vm.goalChips.isEmpty, "打勾类没有「每日目标」可言")

    vm.goalDisplay = 108
    #expect(vm.dailyGoal == nil, "就算硬塞进来也不许留下")
    #expect(try vm.save().dailyGoal == nil, "更不许落库")
}

@MainActor
@Test func 套用同量法的模板也要把目标值清掉() throws {
    // `apply(template:)` 的注释白纸黑字写着「**不带目标值**——九款竞品无一预设数字，
    // 且预设与「随分随力」相违」。可它靠 `measureType` 的 `didSet` 来清，而那个
    // `didSet` 头一句就是 `guard measureType != oldValue else { return }`。
    //
    // 于是：用户在新建页先把目标填成 1080（他心里想的是念佛），再点「模板」选「持咒」
    // ——同为 `.count`，`didSet` 直接早返回，**1080 原样留着**。存下去之后，
    // 持咒这门课的圆满分母是一个他从没为它选过的数。
    //
    // 圆满是这个 App 唯一一处替用户下的判断。判据必须是他自己给的数，
    // 不能是上一次输入的残留。
    let (items, _) = try makeEditorEnv()
    let vm = ItemEditorViewModel(store: items)
    vm.measureType = .count
    vm.dailyGoal = 1080

    // 「持咒」也是 .count，`measureType` 没变，`didSet` 因此不触发。
    vm.apply(template: TemplateCatalog.template(key: "mantra")!)

    #expect(vm.dailyGoal == nil, "套用模板一律不带目标值，量法变没变都一样")
}
