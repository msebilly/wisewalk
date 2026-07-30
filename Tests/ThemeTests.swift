import Testing
import SwiftUI
@testable import WiseWalk

@Test func 主题按深浅色取对应色板() {
    #expect(Theme.resolve(.light).backgroundHex == Palette.Light.background)
    #expect(Theme.resolve(.dark).backgroundHex == Palette.Dark.background)
    #expect(Theme.resolve(.light).accentHex == Palette.Light.accent)
    #expect(Theme.resolve(.dark).accentHex == Palette.Dark.accent)
    #expect(Theme.resolve(.light).fulfilledHex == Palette.Light.fulfilled)
    #expect(Theme.resolve(.dark).fulfilledHex == Palette.Dark.fulfilled)
}

@Test func 主题里每个色值都解析得动() {
    // 常量里一个字符打错，界面上是一片灰，不会报错。
    for theme in [Theme.resolve(.light), Theme.resolve(.dark)] {
        for (hex, name) in theme.allHexes {
            #expect(Contrast.channels(hex) != nil, "\(name) 的 \(hex) 解析不了")
        }
    }
}

@Test func 模板色板每支在两个背景上都够得着图形对比度() {
    // 只验这六个用户选得到的色。**内置模板本身没有颜色**——
    // `PracticeItemStore.create(from:)` 一律写死 `Palette.Light.fulfilled`，
    // 模板带不带色都到不了用户眼前。给 `PracticeTemplate` 加个返回同一常量的
    // `colorHex` 只会让这里变成「把一个常量断言八遍」。
    //
    // 从前这里只问「解析得动吗」。`#D9B679` 当然解析得动，于是它带着浅色底上
    // **1.798:1** 大摇大摆走了进来——**解析得动和看得见是两回事**。
    //
    // 两个底都得问：`ProgressRing` 收的是一个固定 hex，不随 colorScheme 走。
    // 一支色只在浅色下合格，深色模式的用户就看不见自己的环，
    // 而深色模式正是夜课那批人在用的。
    for hex in TemplateCatalog.colorChoices {
        guard let 浅 = Contrast.ratio(hex, Palette.Light.background),
              let 深 = Contrast.ratio(hex, Palette.Dark.background) else {
            Issue.record("模板色 \(hex) 解析不了")
            continue
        }
        // WCAG 1.4.11：非文字内容 3:1。环和图标都只有几个 px 宽。
        #expect(浅 >= 3, "模板色 \(hex) 在浅色底上只有 \(String(format: "%.3f", 浅)):1")
        #expect(深 >= 3, "模板色 \(hex) 在深色底上只有 \(String(format: "%.3f", 深)):1")
    }
}

@Test func 非法色值退回中性灰而不是崩溃或透明() {
    // 透明会让控件凭空消失，比颜色不对更难查。
    #expect(Theme.fallbackHex == "#808080")
    #expect(Contrast.channels(Theme.fallbackHex) != nil)
}

@Test func 圆满状态一定有文字标签() {
    // §7.2 硬约束 4：圆满标记必须「文字 + 颜色」双重编码。
    // 只靠颜色的话，红绿色盲用户看到的是两个一模一样的圆环。
    #expect(FulfillmentBadge.text(for: .fulfilled) == "圆满")
    #expect(FulfillmentBadge.text(for: .fulfilled)?.isEmpty == false)
}

@Test func 未完成与不需做各有自己的说法() {
    #expect(FulfillmentBadge.text(for: .pending) == nil, "未完成不加徽标，避免每天满屏「未完成」")
    #expect(FulfillmentBadge.text(for: .notRequired) == "今日无课")
}

@Test func 进度文案区分计数与计时() {
    #expect(FulfillmentBadge.progressText(total: 500, goal: 1000, unit: "声",
                                          measureType: .count) == "500 / 1000 声")
    #expect(FulfillmentBadge.progressText(total: 500, goal: nil, unit: "声",
                                          measureType: .count) == "500 声")
    #expect(FulfillmentBadge.progressText(total: 1500, goal: 1800, unit: "",
                                          measureType: .duration) == "25:00 / 30:00")
    #expect(FulfillmentBadge.progressText(total: 1500, goal: nil, unit: "",
                                          measureType: .duration) == "25:00")
    #expect(FulfillmentBadge.progressText(total: 1, goal: 1, unit: "",
                                          measureType: .check) == "已完成")
    #expect(FulfillmentBadge.progressText(total: 0, goal: 1, unit: "",
                                          measureType: .check) == "未做")
}

@Test func 进度环能实例化() {
    _ = ProgressRing(progress: 0.5, colorHex: Palette.Light.accent,
                     trackHex: Palette.Light.tertiaryText,
                     isFulfilled: false, iconName: "circle.grid.3x3")
    _ = ProgressRing(progress: 1, colorHex: Palette.Light.fulfilled,
                     trackHex: Palette.Light.tertiaryText,
                     isFulfilled: true, iconName: "circle.grid.3x3")
}

@Test func 进度环把越界进度夹回0到1() {
    // Double 除法在目标为 0 时会给出 inf/nan，喂给 trim 会画出乱七八糟的弧。
    #expect(ProgressRing.clamp(-0.5) == 0)
    #expect(ProgressRing.clamp(1.5) == 1)
    #expect(ProgressRing.clamp(.nan) == 0)
    #expect(ProgressRing.clamp(.infinity) == 1)
    #expect(ProgressRing.clamp(0.42) == 0.42)
}
