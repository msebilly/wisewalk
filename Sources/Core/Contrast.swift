import Foundation

/// WCAG 2.1 相对亮度与对比度。纯函数，不依赖 SwiftUI，因此可以被穷举测试。
///
/// 存在的理由：design-spec §7.2 的每个色值都标着实测对比度，但「标着」不等于「是」。
/// 色板一旦被人顺手调淡半档，文字就会掉到 4.5:1 以下，
/// 而这种退化在模拟器上肉眼几乎看不出来。把公式写进代码，让测试去核对。
enum Contrast {
    /// 解析 `#RRGGBB` 或 `RRGGBB`。非法一律返回 nil，**不做容错猜测**——
    /// 猜错的结果是一个看似合理的对比度，比报错更难发现。
    static func channels(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6,
              s.allSatisfy({ $0.isHexDigit }),
              let v = Int(s, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF), Double((v >> 8) & 0xFF), Double(v & 0xFF))
    }

    /// WCAG 相对亮度，0…1。
    static func relativeLuminance(_ hex: String) -> Double? {
        guard let c = channels(hex) else { return nil }
        func linear(_ v: Double) -> Double {
            let s = v / 255
            return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// 对比度，1.0…21.0。与前后顺序无关。任一色值非法返回 nil。
    static func ratio(_ a: String, _ b: String) -> Double? {
        guard let la = relativeLuminance(a), let lb = relativeLuminance(b) else { return nil }
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}
