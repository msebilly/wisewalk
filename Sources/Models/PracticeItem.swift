import Foundation
import SwiftData

/// 一项定课。念佛、持咒、诵经、拜佛、打坐、抄经、放生、布施……
///
/// **只归档不真删**：真删会让历史流水变成孤儿，
/// 用户三年前的功课不该因为今天不做了就消失。
@Model
final class PracticeItem {
    var id: UUID = UUID()
    var name: String = ""

    /// SF Symbols 名称
    var iconName: String = "circle"
    /// 形如 "#5C7652"
    var colorHex: String = "#5C7652"

    /// `MeasureType` 的原始值
    var measureTypeRaw: String = MeasureType.count.rawValue

    /// 单位量词：遍 / 声 / 拜 / 部 / 卷。计时类与打勾类为空串。
    var unit: String = ""

    /// 每日目标。**nil 表示不设目标。**
    /// 调研过的九款同类应用无一预设数字，且预设数字与「随分随力」相违。
    /// 计时类存**秒**。
    var dailyGoal: Int?

    /// `ScheduleRule` 的原始值
    var scheduleRuleRaw: String = ScheduleRule.daily.rawValue

    /// 提醒时刻，存「当日零点起的分钟数」。6:00 → 360，21:30 → 1290。
    /// 存分钟数而非 Date，是因为提醒的语义是「每天这个钟点」，与具体哪天无关。
    var reminderTimes: [Int] = []

    var sortOrder: Int = 0
    var isArchived: Bool = false

    /// 内置模板标识，用户自建的定课为 nil。
    var templateKey: String?

    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast

    /// CloudKit 要求：关系必须可选，且必须有反向关系。
    /// `.nullify` 保证即便定课项被清理，流水也只是失去归属而不会被连带删除。
    @Relationship(deleteRule: .nullify, inverse: \PracticeSession.item)
    var sessions: [PracticeSession]? = []

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String = "circle",
        colorHex: String = "#5C7652",
        measureType: MeasureType = .count,
        unit: String = "",
        dailyGoal: Int? = nil,
        scheduleRule: ScheduleRule = .daily,
        reminderTimes: [Int] = [],
        sortOrder: Int = 0,
        isArchived: Bool = false,
        templateKey: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorHex = colorHex
        self.measureTypeRaw = measureType.rawValue
        self.unit = unit
        self.dailyGoal = dailyGoal
        self.scheduleRuleRaw = scheduleRule.rawValue
        self.reminderTimes = reminderTimes
        self.sortOrder = sortOrder
        self.isArchived = isArchived
        self.templateKey = templateKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sessions = []
    }

    var measureType: MeasureType {
        get { MeasureType(rawValue: measureTypeRaw) ?? .count }
        set { measureTypeRaw = newValue.rawValue }
    }

    var scheduleRule: ScheduleRule {
        get { ScheduleRule(rawValue: scheduleRuleRaw) }
        set { scheduleRuleRaw = newValue.rawValue }
    }
}
