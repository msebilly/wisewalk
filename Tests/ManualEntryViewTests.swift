import Testing
import SwiftUI
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
@Test func 补记页能实例化() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    _ = ManualEntryView(vm: ManualEntryViewModel(ledger: env.ledger, items: env.items),
                        settings: env.settings)
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
@Test func 数量的说法带正负号而撤销那笔认得出来() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    let now = Date()
    let s = try env.ledger.record(item: item, amount: 108, source: .counter,
                                  startedAt: now, at: now)
    #expect(EntryRow.amountText(s, item: item) == "+108 声")

    let neg = try env.ledger.revoke(s, at: now)
    #expect(EntryRow.amountText(neg, item: item) == "−108 声", "负号要用真的减号 U+2212，不是连字符")
    #expect(EntryRow.isRevocation(neg))
    #expect(!EntryRow.isRevocation(s))
}

@MainActor
@Test func 时长类流水按时长说而不是报秒数() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "打坐", measureType: .duration, unit: "",
                                    dailyGoal: nil, iconName: "figure.mind.and.body",
                                    colorHex: Palette.Light.accent)
    let now = Date()
    let s = try env.ledger.record(item: item, amount: 1800, source: .timer,
                                  startedAt: now, at: now)
    #expect(EntryRow.amountText(s, item: item) == "+30 分", "「+1800」对打坐是没有意义的数字")
}

@MainActor
@Test func 流水的时刻按记那会儿的时区说而不是按此刻手机的时区() throws {
    // ⛔ 全卷唯一一处「历史流水要用当时存下来的那个时区显示」。
    //
    // `timeText` 里那句 `TimeZone(secondsFromGMT: s.tzOffsetMinutes * 60)` 换成
    // `.current`，在北京记的一坐飞到美国再看就整体挪了 15 小时。**账一秒没错，
    // 说谎的是屏幕**，而用户没法从屏幕上分辨这两件事——他只会以为自己那天
    // 凌晨在念佛。这跟「一声都不能多」是同一条线：报告层不许替用户改写他做过的事。
    //
    // 本机时区是 PDT，所以这条测试若写成拿 `.current` 去算期望值，就成了
    // **同一把歪尺子**——实现退回 `.current` 时它照绿。期望值必须是写死的字面量。
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    let 那一刻 = 北京(7, 28, 14, 30)
    let s = try env.ledger.record(item: item, amount: 108, source: .counter,
                                  startedAt: 那一刻, at: 那一刻, timeZone: 北京时间)
    #expect(EntryRow.timeText(s) == "14:30", "显示的是记那会儿的北京时间，不是此刻手机的时区")

    // 撤销那笔继承原记录的时区偏移（`DayLedger.revoke` 里是抄过去的），
    // 所以它跟着原记录一起说北京时间，而不是跟着撤销发生地。
    let neg = try env.ledger.revoke(s, at: 北京(7, 28, 20, 15), timeZone: 北京时间)
    #expect(EntryRow.timeText(neg) == "20:15")
}

@MainActor
@Test func 迁移那笔在流水里被认出来() throws {
    // §6.12：29 万声的起始数若混在日常流水里，日均统计会毫无意义。
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    let vm = ManualEntryViewModel(ledger: env.ledger, items: env.items)
    vm.selectedItem = item
    vm.selectedDayKey = DayKey.today()
    vm.amount = 290_000
    let s = try vm.submitMigrationTotal()
    #expect(EntryRow.isMigration(s))
    #expect(EntryRow.sourceText(s) == "历史累计")
}

@MainActor
@Test func 各来源都有中文说法() throws {
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    let now = Date()
    // **不能只验「非空」。** `!isEmpty` 被两种坏实现满足：一个 `default: "其他"` 的
    // 兜底分支（新加 source 时静默无名），以及把两个分支的字串写反
    //（`.counter` 返回「计时器」）——两种都在说谎，而两种都非空。
    // 所以逐个钉死字面量，再验一遍互不重复。
    let 期望: [SessionSource: String] = [
        .counter: "计数器", .timer: "计时器",
        .manual: "手动补记", .adjustment: "修正",
    ]
    #expect(期望.count == SessionSource.allCases.count, "新加了 source 就得在这儿补上说法")
    for source in SessionSource.allCases {
        let s = try env.ledger.record(item: item, amount: 1, source: source,
                                      startedAt: now, at: now, id: UUID())
        #expect(EntryRow.sourceText(s) == 期望[source], "\(source) 的说法不对")
    }
    #expect(Set(期望.values).count == 期望.count, "两个来源不许共用一个说法，那等于没说")
}

@MainActor
@Test func 打卡类的说法在撤销那笔上是取消而不是已完成() throws {
    // 交付 Task 17 的实现者自己报了这个空洞：`amountText` 的 `.check` 分支
    // （「已完成」/「取消」）当时零覆盖，测试里只造过计数类和计时类。
    //
    // 把那一行的三元判断写反，屏幕就会把撤销那笔说成「已完成」、把原记录说成
    // 「取消」——**一天的实情在修正页上被整个说反了**，而用户正是到这儿来核对的。
    // 与「时刻按存下来的时区说」是同一族：账没错，说谎的是屏幕。
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "早课", measureType: .check, unit: "",
                                    dailyGoal: nil, iconName: "checkmark.circle",
                                    colorHex: Palette.Light.fulfilled)
    let now = Date()
    let s = try env.ledger.record(item: item, amount: 1, source: .manual,
                                  startedAt: now, at: now)
    #expect(EntryRow.amountText(s, item: item) == "已完成")

    let neg = try env.ledger.revoke(s, at: now)
    #expect(EntryRow.amountText(neg, item: item) == "取消", "撤销那笔不许还说「已完成」")
}
