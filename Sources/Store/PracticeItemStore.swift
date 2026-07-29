import Foundation
import SwiftData

enum PracticeItemStoreError: Error, LocalizedError, Equatable {
    /// 已经记过功课的定课不许改量法——旧流水的 `amount` 会被按新量法重新解释。
    case measureTypeLockedByHistory

    /// 这是用户**唯一够得着**的一条错误路径：编辑页的量法选择器本该先禁用，
    /// 只有「编辑页开着时 CloudKit 远端合进一笔流水」才走得到这儿。
    /// 正因为它是最后一道防线，这句话必须是人话——不写就会显示成
    /// 「The operation couldn't be completed. (WiseWalk.PracticeItemStoreError error 0.)」。
    var errorDescription: String? {
        switch self {
        case .measureTypeLockedByHistory:
            return "已经记过功课，计量方式不能再改。要换记法请新建一项，这一项归档即可——过去的记录会照原样保留。"
        }
    }
}

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
    ///
    /// 注意这只保证**新建那一刻**不撞号，不是全局不变量：`reorder` 收的是
    /// 定课管理页上看得见的活跃子集，把它们重排成 `0..<n`，照样会与归档项的旧号相撞。
    /// 可以接受，因为三个 fetch 都带 `SortDescriptor(\.createdAt)` 兜底，
    /// 撞号时顺序是定的而非掷骰子，且用户下次拖拽即自愈。
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
    /// **有历史的定课改不了量法，会掷 `.measureTypeLockedByHistory`。**
    /// `PracticeSession.amount` 是个裸 `Int`，不记自己的单位——计数类当遍数、
    /// 计时类当秒、打勾类恒为 1，全靠定课**当前**的 `measureType` 解释。
    /// 把打坐从计时改成计数，过去一个月每笔 1800 秒会当场显示成「1800 遍」，
    /// 一个用户从没念过的数字。这与「本类型不提供删除方法」是同一条理由：
    /// 已经记下的功课不许被事后重新解释。要换量法就新建一项、旧项归档，
    /// 旧项的历史便永远按原样标注。
    ///
    /// 没有任何历史时放行——刚建错了量法还没记过，本来就该让人改回来。
    ///
    /// 守卫的判据是 `measureType != item.measureType`，而 `measureType` 是从
    /// `measureTypeRaw` 读出来的**有损**计算属性（`MeasureType(rawValue:) ?? .count`）。
    /// 今天够不着：三个 case，所有写入都走 `rawValue`。**但加第四个 case 之前先回来看这里**——
    /// 老版本读到不认识的 raw 会当成 `.count`，用户在老设备上「改个名」就把那个 raw
    /// 静默覆盖掉再同步回新设备，而守卫是相等比较，全程不触发。
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
        if measureType != item.measureType, try hasAnyHistory(item) {
            throw PracticeItemStoreError.measureTypeLockedByHistory
        }
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

    // MARK: - 内部

    /// 这一项有没有记过哪怕一笔功课。
    ///
    /// 不是 `private`：编辑页要靠它把量法选择器**先禁用掉**，
    /// 不能让用户改完点保存才撞上 `.measureTypeLockedByHistory`。
    ///
    /// 存心只查存在性、只取一条，不经 `DayLedger`——`DayLedger` 是账本的**写**入口，
    /// 这里一个字都不写。真要走它就得把 `DayLedger` 注入本类型的构造器，
    /// 而本类型有十来个构造点，为一次存在性查询换掉全部签名不划算。
    func hasAnyHistory(_ item: PracticeItem) throws -> Bool {
        let itemID = item.id
        var descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.item?.id == itemID }
        )
        descriptor.fetchLimit = 1
        return try !context.fetch(descriptor).isEmpty
    }
}
