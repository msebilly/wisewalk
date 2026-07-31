import Foundation
import Observation

enum ItemEditorError: Error, Equatable {
    case emptyName
}

/// 新建或编辑一门定课。
@MainActor
@Observable
final class ItemEditorViewModel {
    var name: String = ""
    var iconName: String = TemplateCatalog.all[0].iconName
    var colorHex: String = TemplateCatalog.colorChoices[0]

    /// 切到计时或勾选时清空量词——「打坐 30 遍」是荒唐的。
    /// 切回计数时**不自动填回**：自动填一个用户没选过的量词，比留空更让人困惑。
    ///
    /// **目标值也一并清掉。** `dailyGoal` 计数类存遍数、计时类存**秒**，两套单位
    /// 之间没有任何有意义的换算：计数类下设的 30（遍）留到计时类就成了
    /// 「打坐 30 秒即圆满」。圆满是这个 App 唯一一处替用户下的判断，
    /// 不许它凭一次量法切换就变成假的。
    var measureType: MeasureType = .count {
        didSet {
            guard measureType != oldValue else { return }
            if measureType != .count { unit = "" }
            dailyGoal = nil
        }
    }

    var unit: String = ""

    /// `nil` 即「不设目标」，此时做了就算圆满。
    /// 非正值一律归为 `nil`——「目标 0 声」不是用户想表达的意思。
    ///
    /// **打勾类一律 `nil`。** 见 `goalChips` 上那段。
    var dailyGoal: Int? {
        get { _dailyGoal }
        set { _dailyGoal = (measureType != .check && (newValue ?? 0) > 0) ? newValue : nil }
    }
    private var _dailyGoal: Int?

    private let store: PracticeItemStore
    private let editing: PracticeItem?
    private var templateKey: String?

    var isEditing: Bool { editing != nil }

    /// 记过功课就不许再改量法——`amount` 是个裸 `Int`，改量法等于把
    /// 过去每一笔重新解释一遍（打坐的 1800 秒会变成「1800 遍」）。
    ///
    /// 在 `init` 里算一次存下来，不做成每次求值的计算属性：
    /// 视图 body 里读它，每帧发一次 fetch 不合适。
    /// 编辑页存活期间用户不可能给这一项记上新功课（要记得先退出去）。
    ///
    /// 查询抛错时**按锁死处理**：宁可挡住一次正当的修改，
    /// 也不能因为查不出来就放行一次会重标历史的修改。
    ///
    /// 这是**快照**不是实时判据：编辑页开着时 CloudKit 远端可能合进一笔流水，
    /// 它就过期成 false，选择器仍可点。**`PracticeItemStore.update` 里那道守卫因此是承重的**——
    /// 数据仍然守得住，坏掉的只是「先禁用再解释」这个体验承诺。
    /// 别把 `update` 的守卫「优化」成信任这个标志。
    private(set) var isMeasureTypeLocked: Bool = false

    init(store: PracticeItemStore, editing: PracticeItem? = nil) {
        self.store = store
        self.editing = editing
        guard let item = editing else { return }
        isMeasureTypeLocked = (try? store.hasAnyHistory(item)) ?? true
        name = item.name
        iconName = item.iconName
        colorHex = item.colorHex
        templateKey = item.templateKey
        // `didSet` 在类**自己的 `init` 里不触发**（Swift 规定，已用 swiftc 实证），
        // 所以下面三句不会互相清掉。但顺序仍按「先量法、再量词与目标」写死：
        // 哪天这段被挪出 `init`（比如抽成一个 `configure()`），didSet 就开始生效，
        // 那时顺序反了会把刚填好的量词和目标一起抹掉，而且**没有测试会红**——
        // 编辑页打开时目标是空的，用户多半只当自己没设过。
        measureType = item.measureType
        unit = item.unit
        // 走 setter 而不是直接写 `_dailyGoal`：同步来的旧数据里可能有
        // 「打勾类带着目标」这种在本版本已经不许存在的组合，进来洗一遍。
        dailyGoal = item.dailyGoal
    }

    /// 界面上填的目标值。
    ///
    /// 计时类**存的是秒、问用户要的是分钟**——没人愿意在「每日目标」里填 1800。
    /// 这一层换算只在这里做一次，别散到视图里去。
    var goalDisplay: Int? {
        get {
            guard let g = dailyGoal else { return nil }
            return measureType == .duration ? g / 60 : g
        }
        set {
            guard let v = newValue, v > 0 else { dailyGoal = nil; return }
            dailyGoal = measureType == .duration ? v * 60 : v
        }
    }

    /// 当前量法该给哪几个快捷档。
    ///
    /// **打勾类一个都不给。** 它一天最多记 1，而 `LedgerMath.isFulfilled` 算的是
    /// `total >= goal`——给它设个 108 就是 `1 >= 108`，用户天天打勾、天天不圆满，
    /// 而且找不出原因：他不会想到是那个自己随手点过的目标数。
    /// 视图据此整节隐藏「每日目标」，`dailyGoal` 的 setter 那一侧也一并挡住。
    var goalChips: [Int?] {
        switch measureType {
        case .duration: TemplateCatalog.durationGoalChips
        case .check: []
        case .count: TemplateCatalog.goalChips
        }
    }

    /// 套用模板。只带出名称、量法、量词与图标，**不带目标值**——
    /// 九款竞品无一预设数字，且预设与「随分随力」相违。
    func apply(template: PracticeTemplate) {
        name = template.name
        measureType = template.measureType
        unit = template.unit
        iconName = template.iconName
        templateKey = template.key
    }

    var canSave: Bool { !trimmedName.isEmpty }

    @discardableResult
    func save(at now: Date = Date()) throws -> PracticeItem {
        let finalName = trimmedName
        guard !finalName.isEmpty else { throw ItemEditorError.emptyName }

        if let item = editing {
            try store.update(item, name: finalName, measureType: measureType, unit: unit,
                             dailyGoal: dailyGoal, iconName: iconName,
                             colorHex: colorHex, at: now)
            return item
        }
        return try store.create(name: finalName, measureType: measureType, unit: unit,
                                dailyGoal: dailyGoal, iconName: iconName,
                                colorHex: colorHex, templateKey: templateKey, at: now)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
