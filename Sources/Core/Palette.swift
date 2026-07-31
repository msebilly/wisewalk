import Foundation

/// design-spec §7.2 的色板。**唯一事实来源**，界面层不许出现字面量色值。
///
/// **不使用 opacity 派生层级**：用透明度调淡等于绕过色板审计——
/// 早期版本正是这么产生了 6 级低于 3:1 的文字，最糟的 Tab 标签只有 2.04:1。
/// 需要更弱的一层就在这里新增一个经过验算的色值，并登记进 `textOnBackground`。
enum Palette {
    /// 浅色 · 晨光暖白
    enum Light {
        static let background = "#FAF7F0"
        static let primaryText = "#2B2620"
        static let secondaryText = "#5E5647"
        /// **最弱文字层到此为止，不得再淡**（§7.2 硬约束 1）
        static let tertiaryText = "#6F6759"
        static let accent = "#A05B35"
        static let fulfilled = "#5C7652"
        /// 晨曦金。**只作光晕，不承载文字**（§7.2 硬约束 2：
        /// 实测叠加 16% 时赭石跌到 4.46:1）。故刻意不登记进 textOnBackground。
        static let glow = "#D9B679"
    }

    /// 深色 · 夜课暖黑。底色刻意**不是纯黑**，避免 OLED 滚动拖影。
    /// （§6.5 隐藏模式才用纯黑，因为那个界面无滚动——第 5 卷的事。）
    enum Dark {
        static let background = "#17140F"
        static let primaryText = "#EFE9DC"
        static let secondaryText = "#B0A897"
        static let tertiaryText = "#9C9385"
        static let accent = "#C98A5E"
        static let fulfilled = "#93A886"
        static let glow = "#D9B679"
    }

    /// 承载文字的色值 → 它所在的背景。守卫测试据此逐一验算。
    /// **新增文字色必须登记到这里**，否则永远不会被对比度审计扫到。
    static let textOnBackground: [(fg: String, bg: String, name: String)] = [
        (Light.primaryText,   Light.background, "浅色/正文"),
        (Light.secondaryText, Light.background, "浅色/次要"),
        (Light.tertiaryText,  Light.background, "浅色/最弱"),
        (Light.accent,        Light.background, "浅色/赭石"),
        (Light.fulfilled,     Light.background, "浅色/圆满绿"),
        (Dark.primaryText,    Dark.background,  "深色/正文"),
        (Dark.secondaryText,  Dark.background,  "深色/次要"),
        (Dark.tertiaryText,   Dark.background,  "深色/最弱"),
        (Dark.accent,         Dark.background,  "深色/赭石"),
        (Dark.fulfilled,      Dark.background,  "深色/圆满绿")
    ]
}
