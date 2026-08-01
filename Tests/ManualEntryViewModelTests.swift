import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeManual() throws
    -> (ManualEntryViewModel, PracticeItemStore, DayLedger, PracticeItem, ModelContext) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let ledger = DayLedger(context: ctx, deviceName: "iPhone·TEST")
    let items = PracticeItemStore(context: ctx)
    let item = try items.create(name: "念佛", measureType: .count, unit: "声",
                                dailyGoal: 1000, iconName: "circle.grid.3x3",
                                colorHex: Palette.Light.fulfilled)
    return (ManualEntryViewModel(ledger: ledger, items: items), items, ledger, item, ctx)
}

private let 北京时间 = TimeZone(identifier: "Asia/Shanghai")!

private func 北京(_ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = 北京时间
    return cal.date(from: c)!
}

/// 「什么都不该写」一律用这句，别写「某一天一条都没有」。
/// 实现若把流水落到别的日子（退回 `.current` 时区、算错 dayKey），
/// 只查一天的断言照样绿，而账本里躺着一笔碎账。
@MainActor
private func 库里一条流水都没有(_ ctx: ModelContext) throws -> Bool {
    try ctx.fetch(FetchDescriptor<PracticeSession>()).isEmpty
}

@MainActor
@Test func 补记到指定历史日期() throws {
    let (vm, _, ledger, item, _) = try makeManual()
    let 写入时刻 = 北京(7, 28, 21, 0)
    vm.selectedItem = item
    vm.selectedDayKey = 20260701
    vm.amount = 500

    let s = try vm.submit(at: 写入时刻, timeZone: 北京时间)

    #expect(s.dayKey == 20260701, "§6.4：dayKey 为所选日期")
    #expect(s.source == .manual)
    #expect(try ledger.total(on: 20260701, itemID: item.id) == 500)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func 补记的写入时刻是真实的不是回拨的() throws {
    // 快照去重排序与第 3 卷诊断都依赖 createdAt。
    // 靠回拨 at: 来补记会连带篡改它，让「这条何时写下」永远说不清。
    let (vm, _, _, item, _) = try makeManual()
    let 写入时刻 = 北京(7, 28, 21, 0)
    vm.selectedItem = item
    vm.selectedDayKey = 20260701
    vm.amount = 500

    let s = try vm.submit(at: 写入时刻, timeZone: 北京时间)

    #expect(s.createdAt == 写入时刻, "createdAt 必须是真实写入时刻")
    #expect(s.tzOffsetMinutes == 480, "时区偏移取当前，不是那天的")
}

@MainActor
@Test func 补记历史日期会补建快照() throws {
    // §6.4：若该日 DaySnapshot 不存在则按当日配置补建。
    // 不补建的话，第 5 卷月历翻到那天会显示「无课」，而明明记着 500 声。
    let (vm, _, ledger, item, _) = try makeManual()
    #expect(try ledger.existingPlan(for: 20260701) == nil, "前提：那天还没有快照")
    vm.selectedItem = item
    vm.selectedDayKey = 20260701
    vm.amount = 1000
    try vm.submit(at: 北京(7, 28, 21, 0), timeZone: 北京时间)

    let plan = try ledger.existingPlan(for: 20260701)
    #expect(plan != nil, "该日快照没补建")
    #expect(plan?.requiredItemIDs == [item.id])
    #expect(try ledger.fulfillment(of: item.id, plan: plan!) == .fulfilled)
}

@MainActor
@Test func 补记不覆盖已有快照() throws {
    // §6.4：若已存在则沿用，**绝不覆盖**。
    let (vm, items, ledger, item, _) = try makeManual()
    let 原计划 = try ledger.plan(for: 20260701, activeItems: [item], dayStartHour: 0, timeZone: 北京时间)
    #expect(原计划.goals[item.id.uuidString] == 1000, "前提：当时目标是 1000")

    // 之后用户把目标改到 3000，再回头补记 7 月 1 日
    try items.update(item, name: "念佛", measureType: .count, unit: "声",
                     dailyGoal: 3000, iconName: "circle.grid.3x3",
                     colorHex: Palette.Light.fulfilled)
    vm.selectedItem = item
    vm.selectedDayKey = 20260701
    vm.amount = 1000
    try vm.submit(at: 北京(7, 28, 21, 0), timeZone: 北京时间)

    let 重读 = try ledger.existingPlan(for: 20260701)!
    #expect(重读.goals[item.id.uuidString] == 1000, "7 月 1 日的目标被改写成 3000 了")
    #expect(try ledger.fulfillment(of: item.id, plan: 重读) == .fulfilled)
}

@MainActor
@Test func 不许补记到未来() throws {
    let (vm, _, ledger, item, ctx) = try makeManual()
    vm.selectedItem = item
    vm.selectedDayKey = 20260729
    vm.amount = 100
    #expect(!vm.canSubmit(at: 北京(7, 28, 21, 0), timeZone: 北京时间))
    #expect(throws: ManualEntryError.futureDay) {
        try vm.submit(at: 北京(7, 28, 21, 0), timeZone: 北京时间)
    }
    // 「一条都没有」而不是「20260729 那天没有」：拦不住的实现多半是把它
    // 落到了今天或别的日子，只查一天的断言照样绿。
    #expect(try 库里一条流水都没有(ctx))
    _ = ledger
    _ = item
}

@MainActor
@Test func 数量必须为正且必须选了定课() throws {
    let (vm, _, _, item, ctx) = try makeManual()
    let 此刻 = 北京(7, 28, 21, 0)
    vm.selectedDayKey = 20260701

    vm.selectedItem = nil
    vm.amount = 100
    #expect(!vm.canSubmit(at: 此刻, timeZone: 北京时间))
    #expect(throws: ManualEntryError.noItemSelected) {
        try vm.submit(at: 此刻, timeZone: 北京时间)
    }

    vm.selectedItem = item
    vm.amount = 0
    #expect(!vm.canSubmit(at: 此刻, timeZone: 北京时间))
    #expect(throws: ManualEntryError.nonPositiveAmount) {
        try vm.submit(at: 此刻, timeZone: 北京时间)
    }

    // 两次都该一个字都没写。先校验后写入与先写入后校验，只有这句分得开。
    #expect(try 库里一条流水都没有(ctx))

    vm.amount = 1
    #expect(vm.canSubmit(at: 此刻, timeZone: 北京时间))
}

@MainActor
@Test func 连点两下只记一笔() throws {
    // 补记这条路一份草稿都没有，`record` 每次新生成 id，
    // 没有任何东西拦得住第二次提交。用户手快点两下就是 1000 声，
    // 而他补记的是 500。
    let (vm, _, ledger, item, ctx) = try makeManual()
    vm.selectedItem = item
    vm.selectedDayKey = 20260701
    vm.amount = 500

    try vm.submit(at: 北京(7, 28, 21, 0), timeZone: 北京时间)
    #expect(throws: ManualEntryError.nonPositiveAmount) {
        try vm.submit(at: 北京(7, 28, 21, 0), timeZone: 北京时间)
    }

    #expect(try ledger.total(on: 20260701, itemID: item.id) == 500, "补的是 500，不是 1000")
    // 全库计数，不是「那天那一项只有一笔」——第二笔若因为任何缘故落到别的日子
    // 或别的项上，按天按项查是照不出来的。
    #expect(try ctx.fetch(FetchDescriptor<PracticeSession>()).count == 1, "全库只该有这一笔")
}

@MainActor
@Test func 记上了才清数记不上要留着让人重试() throws {
    // 纪律第 6 条：清空抢在 record 之前的话，磁盘满时用户填的数就没了，
    // 而他刚敲完 290000 这种数。这里用「记不到未来」当会抛的那一步。
    let (vm, _, _, item, _) = try makeManual()
    vm.selectedItem = item
    vm.selectedDayKey = 20260729
    vm.amount = 500
    vm.note = "早课"

    #expect(throws: ManualEntryError.futureDay) {
        try vm.submit(at: 北京(7, 28, 21, 0), timeZone: 北京时间)
    }

    #expect(vm.amount == 500, "没记上就别把人填的数扔了")
    #expect(vm.note == "早课")
}

@MainActor
@Test func 撤销历史流水负数落在功课那天而不是今天() throws {
    // 修正入口一开，用户第一次能撤销**历史**流水。
    // 负数若落在「今天」，7 月 1 日照旧记着 5000，7 月 28 日凭空多出 −5000——
    // 两天同时说谎。同一天撤同一天的测试照不出这个。
    let (vm, _, ledger, item, _) = try makeManual()
    vm.selectedItem = item
    vm.selectedDayKey = 20260701
    vm.amount = 5000
    let 误记 = try vm.submit(at: 北京(7, 1, 9, 0), timeZone: 北京时间)

    try vm.revoke(误记, at: 北京(7, 28, 21, 0))

    // 用 rawTotal 而不是 total：`total` 把负数 clamp 成 0，
    // 将来若扣成 −10000 它照样报 0，这条断言就成了摆设。
    #expect(try ledger.rawTotal(on: 20260701, itemID: item.id) == 0, "该抵消的是 7 月 1 日")
    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == 0, "7 月 28 日不该多出负数")
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).isEmpty)
}

@MainActor
@Test func 修正是追加负数原记录纹丝不动() throws {
    let (vm, _, ledger, item, _) = try makeManual()
    let now = 北京(7, 28, 9, 0)
    let 误记 = try ledger.record(item: item, amount: 5000, source: .counter,
                                startedAt: now, at: now, timeZone: 北京时间)

    try vm.revoke(误记, at: 北京(7, 28, 21, 0))

    let all = try ledger.sessions(on: 20260728, itemID: item.id)
    #expect(all.count == 2, "原记录必须还在")

    // 名字说的是「纹丝不动」，那就得**逐个字段**验，而不是数条数。
    // 只查「还有一条 id 相同」的话，一个把 `误记.amount` 顺手改成 0 的实现照样全绿——
    // 而 §4.1「只增不改不删」已经被踩穿了。
    let 原记录 = try #require(all.first { $0.id == 误记.id })
    #expect(原记录.amount == 5000, "原记录的数被人动了")
    #expect(原记录.source == .counter, "原记录的来源被人动了")
    #expect(原记录.dayKey == 20260728, "原记录的日子被人动了")
    #expect(原记录.note == nil, "原记录的备注被人动了")

    let 负数 = try #require(all.first { $0.id != 误记.id })
    #expect(负数.amount == -5000)
    #expect(负数.source == .adjustment)

    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func 重复修正同一笔不会扣两次() throws {
    // 用户手快点两下。
    //
    // ⚠️ **这条测试走不到「两台设备各撤一次」那条路。** 它是同一个 context 的顺序
    // 调用，第二次进来时第一笔负数已经在库里，`revoke` 的 note 查重当场命中。
    // 真正的跨设备是两台机器**各自离线**建出两笔 note 相同、UUID 不同的 adjustment，
    // CloudKit 合并后两笔都在，而读侧**没有任何按 note 去重的逻辑**：
    // `+500 +300 −500 −500 = −200`，被 clamp 显示成 0，
    // **用户真做过的那 300 声就此消失。**
    // 修法在读侧（`total`/`rawTotal`/`sessions` 按 note 去重），
    // 但要验得了得有真实 CloudKit 合并——已记进第 3 卷开工前必答的清单。
    let (vm, _, ledger, item, _) = try makeManual()
    let now = 北京(7, 28, 9, 0)
    let a = try ledger.record(item: item, amount: 500, source: .counter,
                              startedAt: now, at: now, timeZone: 北京时间)
    try ledger.record(item: item, amount: 300, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)

    try vm.revoke(a, at: 北京(7, 28, 21, 0))
    try vm.revoke(a, at: 北京(7, 28, 21, 1))

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 300,
            "真念的 300 声不能被第二次撤销吃掉")
    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == 300, "账本原值也必须是 300")
}

@MainActor
@Test func 可以列出某天某项的全部流水供修正() throws {
    let (vm, _, ledger, item, _) = try makeManual()
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)
    try ledger.record(item: item, amount: 500, source: .manual,
                      startedAt: now, at: 北京(7, 28, 10, 0), timeZone: 北京时间)

    let list = try vm.entries(on: 20260728, itemID: item.id)
    #expect(list.count == 2)
    #expect(list.map(\.amount) == [500, 108], "最近写的排在最前，方便改刚记错的那笔")
}

@MainActor
@Test func 迁移用的起始累计带固定备注() throws {
    // §6.12：引导用户把纸本或别家 App 的历史累计一次性补记为一笔起始流水。
    // 打上固定备注，第 3 卷诊断页据此把它与日常流水区分开——
    // 否则「累计 30 万声」里那笔 29 万的起始数会让日均统计毫无意义。
    let (vm, _, ledger, item, _) = try makeManual()
    vm.selectedItem = item
    vm.selectedDayKey = 20260101
    vm.amount = 290_000

    let s = try vm.submitMigrationTotal(at: 北京(7, 28, 21, 0), timeZone: 北京时间)

    #expect(s.note == ManualEntryViewModel.migrationNote)
    #expect(s.amount == 290_000)
    #expect(s.dayKey == 20260101)
    #expect(try ledger.total(on: 20260101, itemID: item.id) == 290_000)
}

@MainActor
@Test func 备注会写进流水() throws {
    let (vm, _, _, item, _) = try makeManual()
    vm.selectedItem = item
    vm.selectedDayKey = 20260701
    vm.amount = 108
    vm.note = "早课"
    let s = try vm.submit(at: 北京(7, 28, 21, 0), timeZone: 北京时间)
    #expect(s.note == "早课")
}

@MainActor
@Test func 空白备注不落库成空串() throws {
    let (vm, _, _, item, _) = try makeManual()
    vm.selectedItem = item
    vm.selectedDayKey = 20260701
    vm.amount = 108
    vm.note = "   "
    let s = try vm.submit(at: 北京(7, 28, 21, 0), timeZone: 北京时间)
    #expect(s.note == nil, "只有空格的备注等于没写")
}

@MainActor
@Test func 没选日子就提交什么都不写() throws {
    // `selectedDayKey` 的初值 0 是「还没选」的哨兵，却一路畅通：
    // `isFuture(0, 20260728)` 是 false，于是快照与流水都会写下 dayKey 0。
    // 那笔功课此后在任何地方都看不见——没有哪一天叫「第 0 天」，
    // 日期选择器回不到那格，修正列表按天查也够不着它去撤销。
    let (vm, _, _, item, ctx) = try makeManual()
    vm.selectedItem = item
    vm.amount = 500

    #expect(!vm.canSubmit(at: 北京(7, 28, 21, 0), timeZone: 北京时间))
    #expect(throws: ManualEntryError.invalidDay) {
        try vm.submit(at: 北京(7, 28, 21, 0), timeZone: 北京时间)
    }
    #expect(try 库里一条流水都没有(ctx))
    #expect(try ctx.fetch(FetchDescriptor<DaySnapshot>()).isEmpty, "快照也不许留")
}

@MainActor
@Test func 一日起始设成凌晨三点时零点后照样补得了今天() throws {
    // 「日历页」与「一日起始」是两套坐标系。若拿 `DayKey.today(dayStartHour: 3)`
    // 当上限去比日历页选出来的 dayKey，凌晨 0 点到 2 点 59 分之间，
    // **日历上的今天那一格会被判成未来**——按钮灰掉、点下去说「明天的功课还没做」。
    // 而这三个小时恰恰是这个设置服务的那批人刚做完夜课、最想补记的时候。
    //
    // 这条测试不给 VM 传任何 dayStartHour：能不能补，本就不该由它说了算。
    let (vm, _, ledger, item, _) = try makeManual()
    let 凌晨一点 = 北京(7, 29, 1, 0)
    vm.selectedItem = item
    vm.selectedDayKey = 20260729          // 日历上的今天
    vm.amount = 500

    #expect(vm.canSubmit(at: 凌晨一点, timeZone: 北京时间))
    let s = try vm.submit(at: 凌晨一点, timeZone: 北京时间)
    #expect(s.dayKey == 20260729)
    #expect(try ledger.rawTotal(on: 20260729, itemID: item.id) == 500)

    // 上限只放到今天为止，明天依旧进不来。
    vm.selectedDayKey = 20260730
    vm.amount = 500
    #expect(!vm.canSubmit(at: 凌晨一点, timeZone: 北京时间))
}

// MARK: - 迁移表单借走的那两个字段

@MainActor
@Test func 迁移表单退出时把借走的两个字段都还回来() throws {
    // ⛔ 纪律 ⑱ 的同一个形状，第二次犯：迁移表单和补记表单共用同一个 `vm`。
    // `amount` 那一处早就发现并擦干净了，`selectedItem` 漏了。
    //
    // 漏的后果比 `amount` 那处更难察觉：用户在补记页选好「念佛」，打开迁移表单
    // 改选「持咒」，想想不对按「取消」——退回补记页，功课选择器停在「持咒」上。
    // 他以为还在念佛那一栏，一点「记上」，**这笔就记到持咒头上**。
    // 数字没错、天数没错，错的是记在谁名下——而圆满是按每门课各自算的。
    //
    // 收进 ViewModel 而不是写在 `MigrationSheet` 的 `onAppear`/`取消` 里：
    // 那是两处，两处就得说两遍，第 2 卷有八次实测说明早晚有一处说错。
    let (vm, items, _, 念佛, _) = try makeManual()
    let 持咒 = try items.create(name: "持咒", measureType: .count, unit: "遍",
                              dailyGoal: nil, iconName: "circle",
                              colorHex: Palette.Light.accent)
    try vm.reloadItems()

    vm.selectedItem = 念佛
    vm.amount = 108

    vm.beginMigration()
    #expect(vm.amount == 0, "迁移表单不该带着补记页那个数进来")
    vm.selectedItem = 持咒
    vm.amount = 290000

    vm.endMigration()
    #expect(vm.selectedItem?.id == 念佛.id, "退出迁移表单必须还回补记页原来选的那门课")
    #expect(vm.amount == 108, "两个字段一起借、一起还")
}

@MainActor
@Test func 迁移表单进来时借的是当前那门课() throws {
    // 借出去的是「当前选中的那门课」，不是 nil——用户多半就是要给这门课记以往累计，
    // 进来还得自己再选一遍是白费手脚。
    let (vm, _, _, 念佛, _) = try makeManual()
    try vm.reloadItems()

    vm.selectedItem = 念佛
    vm.beginMigration()
    #expect(vm.selectedItem?.id == 念佛.id)
}

@MainActor
@Test func 已经记过以往累计的课得说得出记过多少() throws {
    // §6.12 的注脚白纸黑字写着「**只需做一次**」，而 `submitMigrationTotal` 只是
    // 套了个备注的普通 `submit`——**没有一行代码保证那个「一次」**。
    //
    // 他记完发现填错了（比如刚被 3600 倍那条坑过一回），回来重填一遍：
    // 那是**叠加不是覆盖**，账面上凭空多出一份。方向是「多」，
    // 量级就是他一辈子功课的量级。「一声都不能多」在这儿是被一句
    // 承诺过却没兑现的注脚破掉的。
    //
    // 这个 App 只在「圆满」一处替用户下判断，别处一律**把实情说出来，让他自己定**。
    // 所以不是禁止第二次，是让表单一打开就写着「已经记过 3 小时」——
    // 信息前置，他根本走不到误操作那一步；真要再记一笔（翻出第二本旧功课本），
    // 也是他看着实情做的决定。
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let 打坐 = try env.items.create(name: "打坐", measureType: .duration, unit: "",
                                    dailyGoal: nil, iconName: "figure.mind.and.body",
                                    colorHex: Palette.Light.accent)
    let 念佛 = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)

    #expect(try env.ledger.migratedTotal(itemID: 打坐.id) == 0, "没记过就是 0")

    let vm = ManualEntryViewModel(ledger: env.ledger, items: env.items)
    vm.selectedItem = 打坐
    vm.selectedDayKey = DayKey.today()
    vm.amount = 10_800
    let 那一笔 = try vm.submitMigrationTotal()
    #expect(try env.ledger.migratedTotal(itemID: 打坐.id) == 10_800)

    // **不许串课。** 串了的话「念佛已记过 3 小时」，用户会以为自己记错了课去撤，
    // 撤掉的却是打坐那笔真账。
    #expect(try env.ledger.migratedTotal(itemID: 念佛.id) == 0, "另一门课不该跟着有数")

    // 日常那些账一笔都不算数——迁移笔是靠 note 认出来的，
    // 若改成「查这门课的全部流水」，他今天念的 108 声也会被说成「以往累计」。
    _ = try env.ledger.record(item: 念佛, amount: 108, source: .counter,
                              startedAt: Date(), at: Date())
    #expect(try env.ledger.migratedTotal(itemID: 念佛.id) == 0, "日常功课不是以往累计")

    // 记错了撤销掉，就得重新算作「没记过」——否则他撤完还被那句话拦着，
    // 而屏幕上说的「已记过 3 小时」此刻是**假的**。
    _ = try env.ledger.revoke(那一笔, at: Date())
    #expect(try env.ledger.migratedTotal(itemID: 打坐.id) == 0,
            "撤销之后那句话就不能再说了，不然它在说谎")

    // 撤完再记一笔，照样说得出来。
    vm.selectedItem = 打坐
    vm.amount = 7_200
    _ = try vm.submitMigrationTotal()
    #expect(try env.ledger.migratedTotal(itemID: 打坐.id) == 7_200)
}
