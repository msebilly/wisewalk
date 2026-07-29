import Foundation
import Observation

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
    /// 进入本轮之前，今天这一项已经记进账本的数。
    private(set) var committedTotal: Int = 0
    /// 批量增加的步长。§6.6：拨完一串念珠一次加 108。
    private(set) var batchStep: Int = TemplateCatalog.defaultBatchStep

    /// 今天一共多少。用户要看的是这个，而不只是「这一轮念了多少」。
    var dayTotal: Int { committedTotal + count }

    let item: PracticeItem

    private let drafts: DraftStore
    private let ledger: DayLedger
    private var draft: SessionDraft?

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
    func start(
        at now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current
    ) throws {
        self.dayStartHour = dayStartHour
        self.timeZone = timeZone
        let dayKey = DayKey.today(dayStartHour: dayStartHour, now: now, timeZone: timeZone)
        committedTotal = try ledger.total(on: dayKey, itemID: item.id)
        let existing = try drafts.begin(itemID: item.id, source: .counter, at: now)
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
    /// 下限是 0：账本允许为负（那是同步冲突的真实状态），
    /// 但「正在数的这一笔」不可能是负的。
    func undo(at now: Date = Date()) throws {
        try add(-1, at: now)
    }

    private func add(_ delta: Int, at now: Date) throws {
        guard let draft else { return }
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
    /// `add` 的 `guard let draft else { return }` **静默什么都不做**——
    /// 数字冻在 108，他以为在数，其实一声都没进去。
    /// （那 108 声本身丢不了，下次启动 `reconcilePendingDrafts` 会捞出来；
    /// 丢的是他之后又念的那些。）
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
