import Foundation

/// 一条内置模板。
///
/// 模板只预置**名称与计量方式**，不预置经文内容（避开版权与体积），
/// 更**不预置目标值**（见 `TemplateCatalog.goalChips`）。
struct PracticeTemplate: Identifiable, Equatable, Sendable {
    /// 会落库进 `PracticeItem.templateKey`。**已发布的 key 永远不许改。**
    let key: String
    let name: String
    let measureType: MeasureType
    /// 量词：声 / 遍 / 拜。计时类与勾选类为空串。
    let unit: String
    /// SF Symbols 名称。写错不会报错，只会渲染成空白，故有守卫测试盯着。
    let iconName: String

    var id: String { key }
}

/// design-spec §6.6 的内置模板清单。
///
/// 取自三款竞品 App Store 描述的**交叉验证**（万物叁仟 / 八万四千 / 一念计数），非臆测。
/// 其中**持咒**与**抄经**是 spec v2.0 前的范围遗漏——评论里大悲咒 / 心咒 / 往生咒高频出现，
/// 而三款竞品都把持咒当一等公民。
enum TemplateCatalog {
    static let all: [PracticeTemplate] = [
        .init(key: "chanting",   name: "念佛",     measureType: .count,    unit: "声", iconName: "circle.grid.3x3"),
        .init(key: "mantra",     name: "持咒",     measureType: .count,    unit: "遍", iconName: "waveform"),
        .init(key: "sutra",      name: "诵经",     measureType: .count,    unit: "遍", iconName: "book"),
        .init(key: "prostrate",  name: "拜佛",     measureType: .count,    unit: "拜", iconName: "figure.stand"),
        .init(key: "meditation", name: "打坐",     measureType: .duration, unit: "",   iconName: "figure.mind.and.body"),
        // 抄经 spec 写的是「计时或计数」，这里给计时作默认，用户可在编辑页改。
        .init(key: "copying",    name: "抄经",     measureType: .duration, unit: "",   iconName: "pencil.and.outline"),
        .init(key: "offering",   name: "供养",     measureType: .check,    unit: "",   iconName: "flame"),
        // 放生布施 spec 写的是「勾选或计数」，这里给勾选作默认。
        .init(key: "release",    name: "放生布施", measureType: .check,    unit: "",   iconName: "leaf")
    ]

    /// 新建定课时目标值的**可选**快捷档。`nil` 即「不设目标」。
    ///
    /// **「不设目标」排在最前，且是默认值。** 调研过的九款同类应用无一预设数字——
    /// 这不是市场疏忽，是教义约束：定课量因人而异，印光大师所倡「随分随力」即此意。
    /// App 替用户设定「念佛该念 5000 声」既无依据，也可能造成压力。
    ///
    /// 108 是全清单里唯一有客观依据的数字：一串念珠即 108 颗。
    static let goalChips: [Int?] = [nil, 108, 1080]

    /// 批量增加的默认步长。§6.6：拨完一串念珠一次加 108，或从实体计数器誊抄。
    static let defaultBatchStep = 108

    static func template(key: String) -> PracticeTemplate? {
        all.first { $0.key == key }
    }
}
