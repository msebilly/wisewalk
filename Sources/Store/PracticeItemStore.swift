import Foundation
import SwiftData

/// 定课项的唯一写入口。
///
/// **本类型不提供删除方法——不是忘了写，是刻意不给。**
/// 硬删会让历史流水变孤儿，而孤儿流水被 `sessions(on:itemID:)` 的
/// `$0.item?.id == itemID` 挡在所有 per-item 查询之外，
/// 用户三年的功课会从每张报表里凭空蒸发（详见 `PracticeSession.item`）。
/// 要「删」就 `archive`。
@MainActor
final class PracticeItemStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - 读

    /// 未归档的定课，按用户拖拽的顺序。
    /// `sortOrder` 相同时按 `createdAt` 兜底——同步来的两项可能撞上同一个 sortOrder，
    /// 没有第二排序键的话每次取出来的先后就成了掷骰子。
    func activeItems() throws -> [PracticeItem] {
        try context.fetch(FetchDescriptor<PracticeItem>(
            predicate: #Predicate { $0.isArchived == false },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
    }

    func archivedItems() throws -> [PracticeItem] {
        try context.fetch(FetchDescriptor<PracticeItem>(
            predicate: #Predicate { $0.isArchived == true },
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
    }

    func allItems() throws -> [PracticeItem] {
        try context.fetch(FetchDescriptor<PracticeItem>(
            sortBy: [SortDescriptor(\.sortOrder), SortDescriptor(\.createdAt)]
        ))
    }

    /// 按编号取回，**含已归档**。今日页要用它显示「当天登记了、之后才归档」的那些项。
    func item(id: UUID) throws -> PracticeItem? {
        let target = id
        var descriptor = FetchDescriptor<PracticeItem>(predicate: #Predicate { $0.id == target })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: - 写

    /// 新建。`sortOrder` 排到**所有**定课（含已归档）之后——
    /// 只看活跃项的话，归档一项再新建就会撞号，用户把归档项恢复回来时顺序全乱。
    @discardableResult
    func create(
        name: String,
        measureType: MeasureType,
        unit: String,
        dailyGoal: Int?,
        iconName: String,
        colorHex: String,
        templateKey: String? = nil,
        at now: Date = Date()
    ) throws -> PracticeItem {
        let next = (try allItems().map(\.sortOrder).max() ?? -1) + 1
        let item = PracticeItem(
            name: name,
            iconName: iconName,
            colorHex: colorHex,
            measureType: measureType,
            unit: unit,
            dailyGoal: dailyGoal,
            sortOrder: next,
            templateKey: templateKey,
            createdAt: now,
            updatedAt: now
        )
        context.insert(item)
        try context.save()
        return item
    }

    /// 从内置模板新建。**目标默认留空**——模板不预设数字（§6.6）。
    @discardableResult
    func create(
        from template: PracticeTemplate,
        dailyGoal: Int? = nil,
        at now: Date = Date()
    ) throws -> PracticeItem {
        try create(
            name: template.name,
            measureType: template.measureType,
            unit: template.unit,
            dailyGoal: dailyGoal,
            iconName: template.iconName,
            colorHex: Palette.Light.fulfilled,
            templateKey: template.key,
            at: now
        )
    }

    /// 改当前配置。
    ///
    /// **改目标值不影响历史圆满判定**：过去每天的目标定格在 `DaySnapshot` 里，
    /// 由 `DayLedger.plan(for:)` 的「已存在快照绝不改写」守着。此处只管当前配置。
    /// （§6.6 要求这一点在 UI 上明示，否则用户会担心「改了目标以前的记录是不是就废了」。）
    ///
    /// **不收 `scheduleRule` 与 `reminderTimes` 是故意的**——这一卷没有任何界面能设它们，
    /// 不收就等于「原样保留」。将来加排期/提醒界面时，请把它们加成**必填**参数，
    /// 不要图省事写成 `scheduleRule: ScheduleRule = .daily, reminderTimes: [Int] = []`：
    /// 定课管理页每次改名换色都调这个方法，带默认值就等于用户每编辑一次
    /// 就被静默抹掉一次已设好的提醒，而且不报错、不留痕。
    func update(
        _ item: PracticeItem,
        name: String,
        measureType: MeasureType,
        unit: String,
        dailyGoal: Int?,
        iconName: String,
        colorHex: String,
        at now: Date = Date()
    ) throws {
        item.name = name
        item.measureType = measureType
        item.unit = unit
        item.dailyGoal = dailyGoal
        item.iconName = iconName
        item.colorHex = colorHex
        item.updatedAt = now
        try context.save()
    }

    func archive(_ item: PracticeItem, at now: Date = Date()) throws {
        item.isArchived = true
        item.updatedAt = now
        try context.save()
    }

    func unarchive(_ item: PracticeItem, at now: Date = Date()) throws {
        item.isArchived = false
        item.updatedAt = now
        try context.save()
    }

    /// 拖拽结束后调用，按传入顺序重排 `sortOrder`。
    func reorder(_ items: [PracticeItem], at now: Date = Date()) throws {
        for (index, item) in items.enumerated() where item.sortOrder != index {
            item.sortOrder = index
            item.updatedAt = now
        }
        try context.save()
    }
}
