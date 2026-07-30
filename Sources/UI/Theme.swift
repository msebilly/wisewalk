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

extension View {
    func themed() -> some View { modifier(ThemedBackground()) }
}
