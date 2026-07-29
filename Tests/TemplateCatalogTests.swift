import Testing
import UIKit
@testable import WiseWalk

@Test func 内置模板正好八类且顺序稳定() {
    #expect(TemplateCatalog.all.count == 8)
    #expect(TemplateCatalog.all.map(\.name) ==
            ["念佛", "持咒", "诵经", "拜佛", "打坐", "抄经", "供养", "放生布施"])
}

@Test func 持咒与抄经必须在清单里() {
    // 这两类是 spec v2.0 前的范围遗漏，靠三款竞品交叉验证才补回来。
    // 评论里大悲咒/心咒/往生咒高频出现。这条测试是防止它们再被删掉的钉子。
    let keys = Set(TemplateCatalog.all.map(\.key))
    #expect(keys.contains("mantra"), "持咒被删了——它在三款竞品里都是一等公民")
    #expect(keys.contains("copying"), "抄经被删了")
}

@Test func 模板key互不重复() {
    let keys = TemplateCatalog.all.map(\.key)
    #expect(Set(keys).count == keys.count, "key 会落库进 PracticeItem.templateKey，重复会让统计张冠李戴")
}

@MainActor
@Test func 所有模板图标都是有效的SFSymbol() {
    // SF Symbol 名字写错不会报错，只会渲染成一片空白——
    // 这种 bug 能一路溜到 App Store 上。
    var missing: [String] = []
    for t in TemplateCatalog.all where UIImage(systemName: t.iconName) == nil {
        missing.append("\(t.name)(\(t.iconName))")
    }
    #expect(missing.isEmpty, "以下模板的图标不存在，会渲染成空白：\(missing)")
}

@Test func 计数类有量词计时与勾选类没有() {
    for t in TemplateCatalog.all {
        switch t.measureType {
        case .count:
            #expect(!t.unit.isEmpty, "\(t.name) 是计数类却没有量词")
        case .duration, .check:
            #expect(t.unit.isEmpty, "\(t.name) 不是计数类，不该有量词「\(t.unit)」")
        }
    }
}

@Test func 模板一律不预设目标值() {
    // 九款竞品描述全部为「可自定义功课目标」，无一款给出预设数字。
    // 这不是市场疏忽，是教义约束：定课量因人而异，印光大师所倡「随分随力」即此意。
    // PracticeTemplate 根本没有 goal 字段，本测试盯住的是快捷档的默认项。
    #expect(TemplateCatalog.goalChips.first == .some(nil), "「不设目标」必须排在最前")
    #expect(TemplateCatalog.goalChips.compactMap { $0 } == [108, 1080])
}

@Test func 批量步长默认一串念珠() {
    // 108 是全清单里唯一有客观依据的数字：一串念珠即 108 颗。
    #expect(TemplateCatalog.defaultBatchStep == 108)
}

@Test func 可按key取回模板() {
    #expect(TemplateCatalog.template(key: "chanting")?.name == "念佛")
    #expect(TemplateCatalog.template(key: "不存在的key") == nil)
}
