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

@MainActor
@Test func 数量框里的零必须是空框而不是字面的零() {
    // ⛔ 这条是**手点模拟器点出来的**，当时 364 条全绿。
    //
    // 补记页原本写的是 `TextField("0", value: $vm.amount, format: .number)`。
    // `amount` 是 `Int`，初值 0 —— `format: .number` 会把它格式化成
    // **字面的 "0" 填进输入框**，那个 placeholder 于是一辈子不露面。
    //
    // 用户点进去补 500 声，框里那个 0 还在：
    //   光标落在它后面 → "0500" → 500，侥幸对了
    //   光标落在它前面 → "5000" → **5000，十倍**
    //
    // 实测就是十倍：输入 500，弹窗回「记上了 +5000 声」。
    // 老居士补记昨天的 500 声，一眼没看清点了「好」，昨天凭空多出 4500 声。
    // **方向是「多」，量级是十倍，而且一半概率撞上。**
    //
    // 「一声都不能多」在这里不是被算错破掉的，是被一个**没清空的输入框**破掉的。
    var 值 = 0
    let 绑 = Binding(get: { 值 }, set: { 值 = $0 })

    #expect(绑.numericText.wrappedValue == "",
            "0 必须显示成空框：只要框里留着字面的 0，用户输的数就会拼在它身上")

    绑.numericText.wrappedValue = "500"
    #expect(值 == 500, "输 500 就得是 500，不是 5000 也不是 0500")
    #expect(绑.numericText.wrappedValue == "500", "非零照常显示")

    绑.numericText.wrappedValue = ""
    #expect(值 == 0, "清空即 0")

    绑.numericText.wrappedValue = "1a2b3"
    #expect(值 == 123, "numberPad 之外的来路（粘贴、外接键盘）也只收数字")

    绑.numericText.wrappedValue = "99999999999999999999"
    #expect(值 == 123, "撑爆 Int 时保住上一个有效值，不许悄悄归零")
}

@Test func 问以往累计和问补记用的必须是同一套问法() {
    // ⛔ 这条也是**手点模拟器点出来的**，当时 365 条全绿。
    //
    // 补记页对计时类做对了（时 + 分两个转盘），迁移页却是一个裸的数字框——
    // **同一个 App 里两套问法**。而 `amount` 对计时类是【秒】：
    //
    //   打坐三十年，以往累计 5000 小时，他在框里输 5000
    //   → 记成 5000 秒 = 1 小时 23 分
    //   → **丢掉 3599/3600，他三十年的功课只剩一个零头**
    //
    // 方向是「丢」，量级是 3600 倍，而且**必然发生**——没有第二种读法：
    // 框上只写「以往累计」，没有任何地方告诉他这里要填秒。
    //
    // 更狠的是这一笔的处境：注脚白纸黑字写着「只需做一次」，
    // 而 `submitMigrationTotal` 只是套了个备注的普通 `submit`，**不幂等**。
    // 他信了「做一次」，做错了；发现不对再来一次，是**叠加不是覆盖**。
    //
    // 修法不是给迁移页也补一套转盘——补一套就还是两套，下次改一处又漏一处。
    // 是把「这门课的数量该怎么问」收成**一个函数**，两处都问它。
    #expect(AmountInputStyle.forMeasure(.duration) == .duration,
            "计时类必须按时分问；问裸数字就是问秒，而没人会填秒")
    #expect(AmountInputStyle.forMeasure(.count) == .number)
    #expect(AmountInputStyle.forMeasure(.check) == .number)
    #expect(AmountInputStyle.forMeasure(nil) == .number, "还没选课时先给个安全的默认")

    // **不许 `default:` 兜底。** 兜底分支会让日后新加的 measureType 静默按数字问，
    // 而如果那个新类型也是时间量纲，就是同一条 3600 倍在别处重演一遍。
    for m in MeasureType.allCases {
        #expect(AmountInputStyle.allCases.contains(AmountInputStyle.forMeasure(m)),
                "\(m) 没有明确归属")
    }

    // 迁移场景的数字比日常大两三个量级，得确认这一路不溢出也不丢精度：
    // 5000 小时 = 1800 万秒，离 Int 的天花板远得很，但值得钉一下。
    let 五千小时 = DurationField.seconds(hours: 5000, minutes: 0)
    #expect(五千小时 == 18_000_000)
    #expect(DurationField.split(seconds: 五千小时).hours == 5000, "来回一趟不许丢")
}

@MainActor
@Test func 陈述句里的数量不带正负号但量纲照旧() throws {
    // 「已经记过以往累计 +3 小时」——那个「+」会让人以为账本上又多了一行，
    // 而这句话只是在陈述现状。流水行要符号，陈述句不要。
    //
    // 但**量纲一步都不能让**：`plainAmountText` 与 `amountText` 共用同一段判断，
    // 若哪天有人给陈述句另写一份，10800 就会在这儿被说成「10800」。
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let 打坐 = try env.items.create(name: "打坐", measureType: .duration, unit: "",
                                    dailyGoal: nil, iconName: "figure.mind.and.body",
                                    colorHex: Palette.Light.accent)
    let 念佛 = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)

    #expect(EntryRow.plainAmountText(10_800, item: 打坐) == "3 小时",
            "计时类说时长，不许把秒数报出来")
    #expect(EntryRow.plainAmountText(290_000, item: 念佛) == "290000 声")
    #expect(!EntryRow.plainAmountText(10_800, item: 打坐).contains("+"), "陈述句不带号")

    // 流水行那一套没被这次抽取改坏——抽公共函数最容易在这儿翻车。
    let now = Date()
    let s = try env.ledger.record(item: 打坐, amount: 10_800, source: .manual,
                                  startedAt: now, at: now)
    #expect(EntryRow.amountText(s, item: 打坐) == "+3 小时")
    let neg = try env.ledger.revoke(s, at: now)
    #expect(EntryRow.amountText(neg, item: 打坐) == "−3 小时", "真减号 U+2212")
}

@MainActor
@Test func 本机记的那些不必每行都报一遍机器名() throws {
    // ⛔ 每一行都挂着 `iPhone·TUTB`。
    //
    // 它是给第 3 卷的诊断用的——「这笔账是哪台设备记的」。可 CloudKit 还没上，
    // **眼下每个用户都是单设备**，于是每一行报的都是同一台机器：
    // 零信息，却占着一行的宽度。
    //
    // 而且这是一个面向大陆居士的中文界面，`iPhone` 是**英文**
    //（`35e8117` 为了三处英文专门修过一轮，那次只盯着系统补的按钮）。
    //
    // 判据不是「有没有第二台设备」，是**这一笔是不是本机记的**：
    // 本机记的说了等于没说，别的设备记的才是他需要知道的一句。
    let env = try AppEnvironment(container: ModelContainerFactory.inMemory(),
                                 defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!)
    let item = try env.items.create(name: "念佛", measureType: .count, unit: "声",
                                    dailyGoal: nil, iconName: "circle.grid.3x3",
                                    colorHex: Palette.Light.fulfilled)
    let now = Date()
    let 本机记的 = try env.ledger.record(item: item, amount: 108, source: .manual,
                                       startedAt: now, at: now)

    let 这台 = env.ledger.deviceName
    #expect(!这台.isEmpty, "前提：本机的落款不该是空的")

    let 自己 = EntryRow.metaText(本机记的, thisDevice: 这台)
    #expect(自己 == "\(EntryRow.timeText(本机记的)) · 手动补记",
            "本机记的就别报机器名了——他知道是自己记的")
    #expect(!自己.contains("iPhone"), "中文界面里不该每行都冒一个英文机型名")

    // 第 3 卷同步进来的那些，落款不是本机，这时候这句话才有内容。
    本机记的.deviceName = "iPad·X7QP"
    let 别处 = EntryRow.metaText(本机记的, thisDevice: 这台)
    #expect(别处.contains("iPad·X7QP"), "别的设备记的必须说出来——他要知道这笔不是自己在这台机器上记的")

    // 老记录（`deviceName` 默认空串）也不该多出一个孤零零的间隔点。
    本机记的.deviceName = ""
    #expect(!EntryRow.metaText(本机记的, thisDevice: 这台).hasSuffix("·"),
            "落款是空的时候不许留个光秃秃的间隔点")
}
