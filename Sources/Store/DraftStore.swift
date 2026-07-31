import Foundation
import SwiftData

/// 草稿的唯一读写口。
///
/// 与 `DayLedger` 分家但**共用一个 `ModelContext`**——这是刻意的：
/// 同一个上下文才能让「写流水」与「删草稿」落在同一次 `save()` 里（§4.5 第 1 条）。
/// 两个 store 各管各的表，但事务是一个。
@MainActor
final class DraftStore {
    private let context: ModelContext
    private let ledger: DayLedger

    init(context: ModelContext, ledger: DayLedger) {
        self.context = context
        self.ledger = ledger
    }

    // MARK: - 写

    /// 开一份草稿。**同一定课已有草稿时沿用而不是新开一份**——
    /// 否则用户退出计数器再进来就会凭空多出一份，恢复时不知道该信哪个，
    /// 而两份都恢复就是重复记账。
    ///
    /// 但沿用有两个前提，任一不成立就把旧草稿丢掉重开：
    ///
    /// 1. **量法一致**。`source` 是恢复时的分派键（`DraftRecovery.suggestedAmount`：
    ///    `.timer` 按 `updatedAt - startedAt` 折秒，其余直接取 `amount`）。用户改过
    ///    定课的量法之后，旧草稿的 `amount` 与 `startedAt` 在新量法下**每个字段都是错的**：
    ///    拿一份计时草稿当计数用，恢复时会把几小时时长报成「念了几千声」，
    ///    用户一点确认就写进只增不减的账本。
    /// 2. **这笔还没入账**。跨两个 store 文件没有分布式事务，「写流水 + 删草稿」
    ///    那次 save 只是尽力而为，可能流水落了、草稿没删。启动时 `reconcilePendingDrafts`
    ///    会清掉这种草稿，但它**只在启动时跑**——用户不重启 App、在同一次会话里又进了
    ///    计数器，沿用它就等于接下来念的全部白念：`commit` 时 `stage` 按 `sessionID`
    ///    查重，直接返回那笔旧流水，新念的一声也写不进去，而且**不会有任何报错**。
    ///
    /// 两种丢弃都不违背「一声都不能丢」：第 1 种的旧内容在新量法下本就无法换算，
    /// 第 2 种的内容已经在账本里了。
    @discardableResult
    func begin(itemID: UUID, source: SessionSource, at now: Date = Date()) throws -> SessionDraft {
        if let existing = try draft(for: itemID) {
            let sameMeasure = existing.source == source
            let notYetRecorded = !(try ledger.exists(sessionID: existing.sessionID))
            if sameMeasure && notYetRecorded { return existing }
            context.delete(existing)
        }
        let draft = SessionDraft(itemID: itemID, amount: 0,
                                 startedAt: now, updatedAt: now, source: source)
        context.insert(draft)
        try context.save()
        return draft
    }

    /// 更新进行中的量并顺带打心跳。计数器每点一下都会调它。
    ///
    /// 实测每次 save 的开销远在一帧（16.6ms）之下，因此不做节流：
    /// 节流意味着崩溃时会丢掉最后那几声，而「一声都不能丢」正是本产品的立身之本。
    func update(_ draft: SessionDraft, amount: Int, at now: Date = Date()) throws {
        draft.amount = amount
        draft.updatedAt = now
        try context.save()
    }

    /// 只打心跳，不动量也不动起始时刻。计时器用——
    /// 它的量由时间差推算，但需要 `updatedAt` 作崩溃后的「App 活到几点」估计。
    func touch(_ draft: SessionDraft, at now: Date = Date()) throws {
        draft.updatedAt = now
        try context.save()
    }

    /// 提交：写一笔流水并清掉草稿，**同一次 save**（§4.5 第 1 条）。
    ///
    /// 用草稿预生成的 `sessionID` 走 `stage(id:)`：即便本方法在极端情况下
    /// （跨两个 store 文件，进程死在两次落盘之间）留下了没清掉的草稿，
    /// 下次启动的 `reconcilePendingDrafts()` 也会认出它已入账并静默丢弃。
    @discardableResult
    func commit(
        _ draft: SessionDraft,
        item: PracticeItem,
        amount: Int,
        at now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current
    ) throws -> PracticeSession {
        let session = try ledger.stage(
            item: item,
            amount: amount,
            source: draft.source,
            startedAt: draft.startedAt,
            endedAt: now,
            at: now,
            dayStartHour: dayStartHour,
            timeZone: timeZone,
            id: draft.sessionID
        )
        context.delete(draft)
        do {
            try context.save()
        } catch {
            // 实测（SDK 26.5）：save 抛错时 store 会一致地回滚，但 context 的 pending
            // 改动**不会**被清掉。若就这么把错抛出去，那半截「写流水 + 删草稿」的意图
            // 会一直挂在 context 里，被下一次**无关的** save() 顺手提交。
            // 最坏的一条路：commit 失败 → 界面提示「记录失败」→ 用户点「放弃」→
            // discard 里那次 save 把残留的流水一并落盘 → 用户明明放弃了却记上了一笔。
            context.rollback()
            throw error
        }
        return session
    }

    /// 丢弃草稿，不产生任何流水。用户主动放弃时走这里。
    func discard(_ draft: SessionDraft) throws {
        context.delete(draft)
        try context.save()
    }

    // MARK: - 读

    func draft(for itemID: UUID) throws -> SessionDraft? {
        let target = itemID
        var descriptor = FetchDescriptor<SessionDraft>(predicate: #Predicate { $0.itemID == target })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// 全部草稿，按开始时间升序。
    func pendingDrafts() throws -> [SessionDraft] {
        try context.fetch(FetchDescriptor<SessionDraft>(sortBy: [SortDescriptor(\.startedAt)]))
    }

    /// 启动对账：清掉那些流水其实**已经入账**的草稿，返回真正需要用户处理的。
    ///
    /// **这是 §4.5 第 3 条，也是整套崩溃恢复真正的保障。**
    /// 跨两个 store 文件没有分布式事务可言：`commit` 尽力做成一次 `save()`，
    /// 但若进程恰好死在两个 store 各自落盘之间，流水已入账而草稿尚存。
    /// 此时若照着草稿再记一遍，用户的功课就被记成了两倍。
    ///
    /// 每次启动调一次，在向用户弹「要恢复吗」之前。
    func reconcilePendingDrafts() throws -> [SessionDraft] {
        var live: [SessionDraft] = []
        var deletedAny = false
        for draft in try pendingDrafts() {
            if try ledger.exists(sessionID: draft.sessionID) {
                context.delete(draft)
                deletedAny = true
            } else {
                live.append(draft)
            }
        }
        if deletedAny { try context.save() }
        return live
    }
}
