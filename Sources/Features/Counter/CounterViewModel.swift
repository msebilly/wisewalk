import Foundation
import Observation

enum CounterViewModelError: Error, LocalizedError, Equatable {
    /// 还没成功 `start()`（或者已经结束了）就来记数。
    ///
    /// 这不是编程错误，是**运行时状态**：`start()` 会抛（磁盘满、store 打不开），
    /// 抛完之后页面还在、整屏还可点。这里若静默返回，Task 15 的 `perform`
    /// 会把它当成功——响一声、震一下，而那一下什么都没记上。
    /// 念佛的人闭着眼睛靠声音和手感数数，这种假确认他一辈子都发现不了。
    case notCounting

    var errorDescription: String? {
        switch self {
        case .notCounting:
            return "这一页还没准备好，刚才那下没有记上。退出去重新进一次。"
        }
    }
}

/// 计数器的状态机。
///
/// **计数过程中只动草稿，不动账本**（§6.2「结束时才写入一笔 Session」）。
/// 中途写账会让「念到一半退出去」在账本上留下一串碎账，
/// 第 3 卷的诊断页与第 5 卷的明细页都会被淹没。
@MainActor
@Observable
final class CounterViewModel {
    /// 本轮已点的数。
    private(set) var count: Int = 0
    /// 进入本轮之前，`committedDayKey` 那天这一项已经记进账本的数。
    private(set) var committedTotal: Int = 0
    /// 批量增加的步长。§6.6：拨完一串念珠一次加 108。
    private(set) var batchStep: Int = TemplateCatalog.defaultBatchStep

    /// 今天一共多少。用户要看的是这个，而不只是「这一轮念了多少」。
    var dayTotal: Int { committedTotal + count }

    let item: PracticeItem

    private let drafts: DraftStore
    private let ledger: DayLedger
    private var draft: SessionDraft?

    /// `committedTotal` 是**哪一天**的数。
    ///
    /// 它不是一个可以无脑累加的计数器。页面开着的时候日子会翻过去——
    /// 夜课 23:40 进页面、次日 0:30 结束正是常态——那时流水落在新的一天，
    /// 而 `committedTotal` 还是旧那天的。两个数一相加，`dayTotal` 就成了
    /// 哪一天都对不上的游离数字（1000 + 108 = 1108，而「今日」只有 108）。
    /// 账本一声不多不少，说谎的是屏幕，而这是「一声都不能多」的另一种犯法。
    private var committedDayKey: Int = 0

    /// 「一日起始」与时区在 `start()` 时存住，`finish()` 不再单收。
    ///
    /// 若两处各收各的、调用方传得不一致（比如 start 传 3、finish 传 0），
    /// `committedTotal` 算的是 A 天、流水写进 B 天，
    /// 屏幕上的 `dayTotal` 就成了一个**哪一天都对不上**的游离数字。
    /// 账本本身没错（流水按 finish 时刻正确落日），错的是显示。
    /// 存起来让这种不一致**根本不可能发生**，比要求调用方记得传一致更可靠。
    ///
    /// 注意存的是**设置**不是日期：`finish` 仍按它自己那一刻推导 dayKey，
    /// 所以「23:40 开始、次日 0:30 结束」照样按结束时刻决断落哪天。
    private var dayStartHour: Int = 0
    private var timeZone: TimeZone = .current

    init(item: PracticeItem, drafts: DraftStore, ledger: DayLedger) {
        self.item = item
        self.drafts = drafts
        self.ledger = ledger
    }

    /// 进入计数页时调用。
    /// 已有草稿则**接着数**——用户退出去又回来，已经念的不能清零。
    ///
    /// **可以重复调**，Task 15 回到前台时就靠它当 reload：`drafts.begin` 沿用旧草稿、
    /// `count` 从草稿读回来、`committedTotal` 是赋值不是累加，调几次得数都一样。
    /// 别给它加「已经开始过就直接返回」的短路——那样 reload 就废了。
    func start(
        at now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current
    ) throws {
        // 会抛的两步先走完，一个字段都不动；全过了再一次性落到自己身上。
        // 抢在前面赋值的话，`ledger.total` 抛错时会留下「设置是新的、
        // committedDayKey 还是旧的」这种半新半旧的状态——它算不出崩溃，
        // 只会让屏幕上的今日悄悄偏一点，而这正是最难查的那种偏。
        let dayKey = DayKey.today(dayStartHour: dayStartHour, now: now, timeZone: timeZone)
        let total = try ledger.total(on: dayKey, itemID: item.id)
        let existing = try drafts.begin(itemID: item.id, source: .counter, at: now)

        self.dayStartHour = dayStartHour
        self.timeZone = timeZone
        committedDayKey = dayKey
        committedTotal = total
        draft = existing
        count = existing.amount
    }

    /// 点一下。§6.2：整屏可点。
    func tap(at now: Date = Date()) throws {
        try add(1, at: now)
    }

    /// 批量增加。
    func addBatch(at now: Date = Date()) throws {
        try add(batchStep, at: now)
    }

    /// 自定义步长，下限 1。
    func setBatchStep(_ step: Int) {
        batchStep = max(1, step)
    }

    /// 计数途中的撤销。
    ///
    /// 只把草稿减回去，**不产生 `.adjustment` 流水**——这笔账压根还没记上，无从撤起。
    /// 若在这里追加负数流水，账本上会冒出一笔没有对应正数的调整，诊断页无法解释。
    ///
    /// 下限是 0。账本的当日求和**允许为负**——`.adjustment` 流水可正可负
    /// （design-spec §3，`:149` 与 `:173`），而各设备的流水各自独立同步，
    /// 一笔负的修正完全可能先于它要修正的那笔正数到达（与 §5.6 同一个到达顺序问题）。
    /// 但**「正在数的这一笔」不可能是负的**：它还没进账本，没有任何东西可修正。
    func undo(at now: Date = Date()) throws {
        try add(-1, at: now)
    }

    /// 没有草稿就**抛错**，不许静默返回。
    /// 静默返回时视图收不到任何信号，会照常给出「记上了」的音效与震动，
    /// 而这一下根本没记上——闭着眼睛数数的人永远发现不了。
    private func add(_ delta: Int, at now: Date) throws {
        guard let draft else { throw CounterViewModelError.notCounting }
        count = max(0, count + delta)
        try drafts.update(draft, amount: count, at: now)
    }

    /// 结束：写一笔流水并清掉草稿（同一次 save）。
    /// 一声没念就直接丢弃草稿，不留空账、也不留会触发恢复弹窗的空草稿。
    /// 已经结束过则什么也不做，返回 nil。
    ///
    /// **`draft = nil` 一律在会抛的那步成功之后**。放在前面的话：
    /// `commit` 抛错（磁盘满、I/O 错）→ `DraftStore` 回滚，草稿还活着、账本没记；
    /// 而这里已经把它置 nil、`count` 还停在 108。此后用户再点屏幕，
    /// `add` 抛 `.notCounting`——视图会弹错误提示，
    /// 而不是让数字冻在 108、让他以为在数。
    /// （那 108 声本身丢不了，下次启动 `reconcilePendingDrafts` 会捞出来。）
    /// 保持 draft 不动，用户可以直接再按一次「结束」重试。
    @discardableResult
    func finish(
        at now: Date = Date()
    ) throws -> PracticeSession? {
        guard let draft else { return nil }

        guard count > 0 else {
            try drafts.discard(draft)
            self.draft = nil
            return nil
        }

        let session = try drafts.commit(
            draft, item: item, amount: count,
            at: now, dayStartHour: dayStartHour, timeZone: timeZone
        )
        self.draft = nil
        if session.dayKey != committedDayKey {
            // 页面开着的时候日子翻过去了：这一笔落在新的一天，
            // 旧那天的 `committedTotal` 跟它没关系，累加上去屏幕就会替用户
            // 多报一整天（1000 + 108 = 1108，而「今日」只有 108）。
            //
            // 归零而不是重读账本——重读要 fetch，而这里已经在 commit 成功**之后**，
            // 那次 fetch 抛错会让用户读到「记录失败」，可账其实记上了，那是更坏的谎。
            // 归零的代价是新那天若已有别处记的流水会漏报，方向是「丢」不是「多」，
            // 且下次 `start()`（Task 15 回到前台就调）一次就补齐。
            committedDayKey = session.dayKey
            committedTotal = 0
        }
        committedTotal += count
        count = 0
        return session
    }

    /// 放弃本轮：草稿与账本都不留痕。
    /// 同样，`discard` 成功之后才清自己的状态。
    func abandon() throws {
        guard let draft else { return }
        try drafts.discard(draft)
        self.draft = nil
        count = 0
    }
}
