import Foundation

/// 计量方式。
/// **rawValue 会写进数据库，已发布的字符串永远不许改。**
enum MeasureType: String, Codable, CaseIterable, Sendable {
    /// 计数：念佛、持咒、拜佛
    case count
    /// 计时：打坐、诵经。数值一律存**秒**
    case duration
    /// 打勾：早晚课、放生、布施
    case check
}

/// 流水来源。用于诊断页回答「这笔账是怎么来的」。
enum SessionSource: String, Codable, CaseIterable, Sendable {
    /// 计数器点击
    case counter
    /// 计时器结束
    case timer
    /// 手动补录
    case manual
    /// 修正。**只有这一种可以为负**——撤销就是追加一笔负数 adjustment
    case adjustment
}

/// 排班规则。存为字符串，形式见 rawValue。
enum ScheduleRule: Equatable, Hashable, Sendable {
    case daily
    /// 公历星期，1 = 周日 … 7 = 周六，与 `Calendar.component(.weekday)` 一致
    case weekdays(Set<Int>)
    /// 指定农历日，如初一十五
    case lunarDays(Set<Int>)
    /// 六斋日
    case lunarSixZhai
    /// 十斋日
    case lunarTenZhai
    /// 诸佛菩萨圣诞日
    case lunarBuddhaDays
}

extension ScheduleRule {
    var rawValue: String {
        switch self {
        case .daily:
            return "daily"
        case .weekdays(let days):
            return "weekdays:" + Self.encode(days)
        case .lunarDays(let days):
            return "lunar:" + Self.encode(days)
        case .lunarSixZhai:
            return "lunar:sixzhai"
        case .lunarTenZhai:
            return "lunar:tenzhai"
        case .lunarBuddhaDays:
            return "lunar:buddhaDays"
        }
    }

    /// 无法识别一律退化为 `.daily`。
    /// 宁可让用户多看见一次提醒，也不能因为解析失败让功课从清单上消失。
    init(rawValue: String) {
        switch rawValue {
        case "lunar:sixzhai":
            self = .lunarSixZhai
        case "lunar:tenzhai":
            self = .lunarTenZhai
        case "lunar:buddhaDays":
            self = .lunarBuddhaDays
        default:
            if let body = Self.body(of: rawValue, prefix: "weekdays:") {
                let days = Self.decode(body)
                self = days.isEmpty ? .daily : .weekdays(days)
            } else if let body = Self.body(of: rawValue, prefix: "lunar:") {
                let days = Self.decode(body)
                self = days.isEmpty ? .daily : .lunarDays(days)
            } else {
                self = .daily
            }
        }
    }

    private static func encode(_ days: Set<Int>) -> String {
        days.sorted().map(String.init).joined(separator: ",")
    }

    private static func decode(_ body: String) -> Set<Int> {
        Set(body.split(separator: ",").compactMap { Int($0) })
    }

    private static func body(of raw: String, prefix: String) -> String? {
        guard raw.hasPrefix(prefix) else { return nil }
        return String(raw.dropFirst(prefix.count))
    }
}
