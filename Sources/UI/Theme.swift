import SwiftUI

extension Color {
    /// `#RRGGBB` → Color。非法色值退回中性灰。
    ///
    /// 为什么不退回透明：透明会让控件凭空消失，比颜色不对更难查。
    /// 为什么不 fatalError：颜色是装饰层，不值得为它崩掉用户正在数的功课。
    /// 我们自己的常量有 `主题里每个色值都解析得动` 那条测试兜着，
    /// 这条退路只为同步来的、未来版本写入的未知色值准备。
    init(hex: String) {
        guard let c = Contrast.channels(hex) else {
            self = Color(hex: Theme.fallbackHex)
            return
        }
        self = Color(.sRGB, red: c.r / 255, green: c.g / 255, blue: c.b / 255, opacity: 1)
    }
}

/// 一套解析好的界面颜色。
///
/// 刻意同时保留 hex 字符串和 `Color`：hex 用于测试与对比度审计（`Color` 无法比较），
/// `Color` 用于渲染。
struct Theme: Equatable, Sendable {
    static let fallbackHex = "#808080"

    let backgroundHex: String
    let primaryTextHex: String
    let secondaryTextHex: String
    let tertiaryTextHex: String
    let accentHex: String
    let fulfilledHex: String
    let glowHex: String

    var background: Color { Color(hex: backgroundHex) }
    var primaryText: Color { Color(hex: primaryTextHex) }
    var secondaryText: Color { Color(hex: secondaryTextHex) }
    var tertiaryText: Color { Color(hex: tertiaryTextHex) }
    var accent: Color { Color(hex: accentHex) }
    var fulfilled: Color { Color(hex: fulfilledHex) }
    /// 晨曦金。**只作光晕，不承载文字**——实测叠在背景上只有 4.46:1。
    var glow: Color { Color(hex: glowHex) }

    var allHexes: [(String, String)] {
        [(backgroundHex, "background"), (primaryTextHex, "primaryText"),
         (secondaryTextHex, "secondaryText"), (tertiaryTextHex, "tertiaryText"),
         (accentHex, "accent"), (fulfilledHex, "fulfilled"), (glowHex, "glow")]
    }

    static func resolve(_ scheme: ColorScheme) -> Theme {
        scheme == .dark
            ? Theme(backgroundHex: Palette.Dark.background,
                    primaryTextHex: Palette.Dark.primaryText,
                    secondaryTextHex: Palette.Dark.secondaryText,
                    tertiaryTextHex: Palette.Dark.tertiaryText,
                    accentHex: Palette.Dark.accent,
                    fulfilledHex: Palette.Dark.fulfilled,
                    glowHex: Palette.Dark.glow)
            : Theme(backgroundHex: Palette.Light.background,
                    primaryTextHex: Palette.Light.primaryText,
                    secondaryTextHex: Palette.Light.secondaryText,
                    tertiaryTextHex: Palette.Light.tertiaryText,
                    accentHex: Palette.Light.accent,
                    fulfilledHex: Palette.Light.fulfilled,
                    glowHex: Palette.Light.glow)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.resolve(.light)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// 挂在根视图上，随系统深浅色切换自动换板。
///
/// ⚠️ **这里只管环境与 tint，不管底色。** 底色要用 `.pageBackground()` 挂在
/// `NavigationStack` **内部**的每一页上，理由见 `PageBackground`。
struct ThemedBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let theme = Theme.resolve(scheme)
        return content
            .environment(\.theme, theme)
            .background(theme.background.ignoresSafeArea())
            .tint(theme.accent)
    }
}

/// 页面底色。**必须挂在 `NavigationStack` 内部的每一页上。**
///
/// `NavigationStack` 自己画一层不透明的系统底（浅色纯白 `#FFFFFF`、深色纯黑
/// `#000000`）。`ThemedBackground` 挂在栈**外面**，它那句
/// `.background(theme.background)` 整个被盖住——**那行是死代码，一像素都没画出来过**。
/// 2026-07-31 跑 Step 12 端到端验证时截图采样才发现：
/// 浅色实测 `#FFFFFF`（色板写的是 `#FAF7F0`）、深色实测 `#000000`（色板写的是 `#17140F`）。
///
/// **要紧的不是好不好看，是 `Palette.audited` 那 11 条对比度断言审的是一个
/// 用户从没见过的底色。** 一条测试审的东西不在屏幕上，它就不是它名字说的那件事。
///
/// 方向上是安全的那一侧（纯白比暖纸更亮、纯黑比暖深底更暗，前景对比度只会更高，
/// 不会更低），所以这不是无障碍回归；但审计与实景对不上这件事本身必须修。
///
/// `.scrollContentBackground(.hidden)` 是给 `List` / `Form` 用的——`ScrollView`
/// 本身透明，不加也行，加上是为了将来某页换成 `List` 时不必再想起这件事。
struct PageBackground: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.background.ignoresSafeArea())
    }
}

extension View {
    func themed() -> some View { modifier(ThemedBackground()) }
    func pageBackground() -> some View { modifier(PageBackground()) }
}

extension Binding {
    /// `.alert(_:isPresented:)` 用的可写派生绑定：有值就弹，系统写回 `false` 时清成 `nil`。
    ///
    /// ⛔ **不要写 `.constant(x != nil)`。** SwiftUI 关闭 alert 时会往 `isPresented`
    /// 写 `false`，而 `.constant` 把这次写入丢掉。只要有一条关闭路径不经过按钮闭包
    /// （VoiceOver 的 escape 手势、系统主动收起、日后 SwiftUI 行为变化），
    /// 底下那个 `failure` / `toast` 仍然非 nil，alert 立刻重新弹出来——
    /// **用户被困在一个点不掉的弹窗里，退不出这一页。**
    ///
    /// 抽成一处是因为全卷有六个地方要写它。要说六遍的话，早晚有一处说错。
    static func presenting<T>(_ source: Binding<T?>) -> Binding<Bool> where Value == Bool {
        Binding(get: { source.wrappedValue != nil },
                set: { if !$0 { source.wrappedValue = nil } })
    }
}

extension Binding where Value == Int {
    /// 数量输入框绑这个，**不要绑 `value:` + `format: .number`**。
    ///
    /// `TextField(value:format:)` 会把 `0` 格式化成**字面的 "0" 填进框里**，
    /// 那个 placeholder 于是一辈子不露面。用户点进去补 500 声，那个 0 还在：
    ///
    ///     光标落在它后面 → "0500" → 500，侥幸对了
    ///     光标落在它前面 → "5000" → **5000，十倍**
    ///
    /// 实测就是十倍。老居士补记昨天的 500 声，一眼没看清点了「好」，
    /// 昨天凭空多出 4500 声。**方向是「多」，量级是十倍，一半概率撞上。**
    ///
    /// 撑爆 `Int` 时保住上一个有效值：让用户看见「输不进去」，
    /// 好过悄悄归零之后他没发现，按着 0 记了一笔。
    var numericText: Binding<String> {
        Binding<String>(
            get: { wrappedValue == 0 ? "" : String(wrappedValue) },
            set: { 新值 in
                let 数字 = 新值.filter(\.isNumber)
                if 数字.isEmpty { wrappedValue = 0 }
                else if let n = Int(数字) { wrappedValue = n }
            }
        )
    }
}
