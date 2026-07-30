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
    let 原计划 = try ledger.plan(for: 20260701, activeItems: [item])
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
    let (vm, _, ledger, item, _) = try makeManual()
    vm.selectedItem = item
    vm.selectedDayKey = 20260701
    vm.amount = 500

    try vm.submit(at: 北京(7, 28, 21, 0), timeZone: 北京时间)
    #expect(throws: ManualEntryError.nonPositiveAmount) {
        try vm.submit(at: 北京(7, 28, 21, 0), timeZone: 北京时间)
    }

    #expect(try ledger.total(on: 20260701, itemID: item.id) == 500, "补的是 500，不是 1000")
    #expect(try ledger.sessions(on: 20260701, itemID: item.id).count == 1)
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

    #expect(try ledger.total(on: 20260701, itemID: item.id) == 0, "该抵消的是 7 月 1 日")
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
    #expect(all.contains { $0.id == 误记.id })
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func 重复修正同一笔不会扣两次() throws {
    // 用户手快点两下，或两台设备各撤一次。
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
