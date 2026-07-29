import Testing
import Foundation
@testable import WiseWalk

@Test func 对比度公式对得上已知锚点() {
    #expect(abs((Contrast.ratio("#000000", "#FFFFFF") ?? 0) - 21.0) < 0.001, "纯黑对纯白必须是 21:1")
    #expect(abs((Contrast.ratio("#FFFFFF", "#FFFFFF") ?? 0) - 1.0) < 0.001, "同色必须是 1:1")
    #expect(abs((Contrast.ratio("#777777", "#FFFFFF") ?? 0) - 4.478) < 0.01, "#777 对白是 WCAG 文档里的经典值")
}

@Test func 对比度与前后顺序无关() {
    let a = Contrast.ratio("#2B2620", "#FAF7F0")
    let b = Contrast.ratio("#FAF7F0", "#2B2620")
    #expect(a != nil)
    #expect(a == b, "对比度是对称的，谁在前谁在后都一样")
}

@Test func 非法色值返回nil而不是悄悄给个假数() {
    #expect(Contrast.ratio("#12345", "#FFFFFF") == nil, "五位十六进制应判非法")
    #expect(Contrast.ratio("赭石", "#FFFFFF") == nil)
    #expect(Contrast.relativeLuminance("#GGGGGG") == nil)
    #expect(Contrast.relativeLuminance("FAF7F0") != nil, "省略井号仍应接受")
}

@Test func 色板对比度与设计规范逐一吻合() {
    // 期望值不是从 spec 抄的，是独立算过一遍确认无误的。
    // 若这条变红，先怀疑色板被人改了，而不是怀疑这里的数字。
    let expected: [(fg: String, bg: String, want: Double, name: String)] = [
        (Palette.Light.primaryText,   Palette.Light.background, 14.01, "浅色/正文"),
        (Palette.Light.secondaryText, Palette.Light.background,  6.77, "浅色/次要"),
        (Palette.Light.tertiaryText,  Palette.Light.background,  5.22, "浅色/最弱"),
        (Palette.Light.accent,        Palette.Light.background,  4.86, "浅色/赭石"),
        (Palette.Light.fulfilled,     Palette.Light.background,  4.71, "浅色/圆满绿"),
        (Palette.Dark.primaryText,    Palette.Dark.background,  15.18, "深色/正文"),
        (Palette.Dark.secondaryText,  Palette.Dark.background,   7.78, "深色/次要"),
        (Palette.Dark.tertiaryText,   Palette.Dark.background,   6.06, "深色/最弱"),
        (Palette.Dark.accent,         Palette.Dark.background,   6.37, "深色/赭石"),
        (Palette.Dark.fulfilled,      Palette.Dark.background,   7.16, "深色/圆满绿")
    ]
    for e in expected {
        let got = Contrast.ratio(e.fg, e.bg)
        #expect(got != nil, "\(e.name) 色值非法")
        #expect(abs((got ?? 0) - e.want) < 0.01,
                "\(e.name) \(e.fg) on \(e.bg) 实算 \(String(format: "%.2f", got ?? 0))，规范写的是 \(e.want)")
    }
}

@Test func 所有承载文字的色值都不低于AA标准() {
    for entry in Palette.textOnBackground {
        let r = Contrast.ratio(entry.fg, entry.bg) ?? 0
        #expect(r >= 4.5,
                "\(entry.name) 只有 \(String(format: "%.2f", r)):1，低于 WCAG AA 的 4.5:1。§7.2 硬约束 1：最弱文字层到此为止，不得再淡")
    }
}

@Test func 承载文字的色值必须逐一登记() {
    // 与 CloudKitConstraintTests 的白名单同一个思路：
    // 新增一个文字色而忘了登记，它就永远不会被对比度审计扫到。
    let registered = Set(Palette.textOnBackground.map(\.fg))
    let allTextColors = [
        Palette.Light.primaryText, Palette.Light.secondaryText, Palette.Light.tertiaryText,
        Palette.Light.accent, Palette.Light.fulfilled,
        Palette.Dark.primaryText, Palette.Dark.secondaryText, Palette.Dark.tertiaryText,
        Palette.Dark.accent, Palette.Dark.fulfilled
    ]
    for c in allTextColors {
        #expect(registered.contains(c), "\(c) 未登记进 Palette.textOnBackground，不会被对比度审计扫到")
    }
}

@Test func 晨曦金不承载文字() {
    // §7.2 硬约束 2：光晕封顶 12%，赭石文字不得出现在光晕最浓处。
    // 最省事的守法是根本不让 glow 进文字色清单。
    let registered = Set(Palette.textOnBackground.map(\.fg))
    #expect(!registered.contains(Palette.Light.glow), "晨曦金是光晕，不该出现在文字色清单里")
}
