import Foundation
import Observation

/// 计时器的状态机。
///
/// **时长一律是 `now − startedAt`**（§6.3）——绝不累加 Timer 的滴答数。
/// App 一进后台 Timer 就停，靠累加会少记一大截：
/// 用户打坐半小时、锁屏把手机放兜里，回来只记了三分钟。
@MainActor
@Observable
final class TimerViewModel {
    /// 心跳间隔：每 10 秒把「App 此刻还活着」写进草稿。
    ///
    /// ⚠️ **10 秒不是崩溃能损失的时长上限。** 心跳由 Task 16 的
    /// `Timer.publish(every: 1, on: .main, in: .common)` 驱动，而那个 Timer
    /// **一进后台就停**。用户起坐、锁屏、把手机放在一边坐半小时——心跳在锁屏后
    /// 几秒就断了，草稿的 `updatedAt` 从此定格。这半小时里 App 若被系统回收
    /// （长时间后台、又没有音频会话，打坐恰恰是最容易被回收的场景），
    /// 下次启动 `DraftRecovery.suggestedAmount` 只能按定格的 `updatedAt` 推算，
    /// **整整半小时只剩十来秒**；而恢复弹窗只有「接受」和「拒绝」，改不了数。
    ///
    /// 真正的上限是「最后一次进入后台之后坐的那一段」。
    /// 不按「现在」推算是**故意**的——App 可能崩在三天前，用「现在」会给用户
    /// 记上 72 小时的打坐，那是「多」，比「丢」坏得多。这里方向是「丢」，
    /// 用户看得见（弹窗上的数字明显偏小），可以走补记（Task 11）补齐。
    /// 要根治得申请后台执行权限，**本卷不做**。
    ///
    /// 10 秒这个值本身管的是另一件事：**前台**打坐时被回收能损失多少。
    static let heartbeatInterval: TimeInterval = 10

    private(set) var elapsed: Int = 0
    private(set) var isRunning = false
    /// 进入本轮之前，`committedDayKey` 那天这一项已经记进账本的秒数。
    private(set) var committedTotal: Int = 0

    /// 今天一共坐了多久。用户要看的是这个，而不只是「这一轮坐了多久」。
    ///
    /// ⚠️ 页面开着的时候日子若翻过去，这个数在**下一次 `finish()` 或 `start()` 之前**
    /// 是旧那天的（夜坐 23:59 时它还带着白天那几坐）。落库的账本不受影响，
    /// 圆满与否由 `TodayViewModel` 读账本判定，与这里无关。
    var dayTotal: Int { committedTotal + elapsed }

    /// 大号走时文本。
    var clockText: String { DurationFormat.clock(elapsed) }

    let item: PracticeItem

    private let drafts: DraftStore
    private let ledger: DayLedger
    private var draft: SessionDraft?
    private var startedAt: Date?
    private var lastHeartbeat: Date = .distantPast

    /// `committedTotal` 是**哪一天**的数。
    ///
    /// 它不是一个可以无脑累加的计数器。夜坐 23:40 起坐、次日 0:10 收坐是常态，
    /// 那时流水落在新的一天，而 `committedTotal` 还是旧那天的。两个数一相加，
    /// `dayTotal` 就成了哪一天都对不上的游离数字（3600 + 1800 = 5400，
    /// 而「今日」只有 1800）。账本一秒不多不少，说谎的是屏幕，
    /// 而这是「一声都不能多」的另一种犯法。
    private var committedDayKey: Int = 0

    /// 「一日起始」与时区在 `start()` 时存住，`finish()` 不再单收。
    ///
    /// 若两处各收各的，`committedTotal` 算的是 A 天、流水写进 B 天，
    /// 屏幕上的 `dayTotal` 就成了哪一天都对不上的游离数字。
    /// 这不是假想：Task 16 的规格里 `start(dayStartHour: settings.dayStartHour)`
    /// 而 `commit()` 只写 `vm.finish()`，两边差着用户设的那个一日起始。
    /// 存起来让这种不一致**根本不可能发生**，比要求调用方记得传一致更可靠。
    ///
    /// 注意存的是**设置**不是日期：`finish` 仍按它自己那一刻推导 dayKey，
    /// 所以「23:40 起坐、次日 0:10 收坐」照样按收坐时刻决断落哪天。
    private var dayStartHour: Int = 0
    private var timeZone: TimeZone = .current

    init(item: PracticeItem, drafts: DraftStore, ledger: DayLedger) {
        self.item = item
        self.drafts = drafts
        self.ledger = ledger
    }

    /// 进入计时页时调用。
    /// 已有草稿则**沿用它的起始时刻**——用户切出去接了个电话再回来，不该从零重计。
    ///
    /// **可以重复调**，Task 16 回到前台时就靠它当 reload：`drafts.begin` 沿用旧草稿、
    /// `startedAt` 从草稿读回来、`committedTotal` 是赋值不是累加，调几次得数都一样。
    /// 别给它加「已经在跑就直接返回」的短路——那样 reload 就废了。
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
        let existing = try drafts.begin(itemID: item.id, source: .timer, at: now)

        self.dayStartHour = dayStartHour
        self.timeZone = timeZone
        committedDayKey = dayKey
        committedTotal = total
        draft = existing
        startedAt = existing.startedAt
        lastHeartbeat = existing.updatedAt
        isRunning = true
        refresh(at: now)
    }

    /// 由界面每秒调一次，只算不写盘。
    /// 时钟回拨时不给负数——负的时长写进账本会被 clamp 掩盖，不如在这里就拦住。
    func refresh(at now: Date = Date()) {
        guard let startedAt else { return }
        // ⚠️ 已知取舍：整个计时口径是**挂钟差值**，不是单调时钟。
        // 时钟向后跳超过已计时长时，这里会被 `max(0,)` 压成 0——用户眼看着秒数归零。
        // 同一个根因还会让崩溃恢复算不出时长（见 `DraftRecovery.suggestedAmount` 的
        // `updatedAt < startedAt` 分支，以及 Task 19 discard 处的注释）。
        //
        // 触发要同时满足「时钟回拨超过已计时长」，iOS 上的 NTP 校正都是亚秒级，
        // 够得上的只有用户手动改表。真要根治得换 `ContinuousClock` 并把已计秒数
        // 写进草稿的 `amount`（现在心跳只 `touch` 不写量）。**这一卷不做。**
        elapsed = max(0, Int(now.timeIntervalSince(startedAt)))
    }

    /// 心跳：把「App 此刻还活着」写进草稿。到间隔才写，避免每秒一次写盘。
    ///
    /// 崩溃恢复时用 `updatedAt` 而不是「现在」来估算时长——
    /// App 可能崩在三天前，用「现在」会给用户记上 72 小时的打坐。
    func heartbeatIfNeeded(at now: Date = Date()) throws {
        guard isRunning, let draft else { return }
        guard now.timeIntervalSince(lastHeartbeat) >= Self.heartbeatInterval else { return }
        try drafts.touch(draft, at: now)
        lastHeartbeat = now
    }

    /// 结束：按秒记一笔并清掉草稿。
    /// 不足一秒直接丢弃，不留空账、也不留会触发恢复弹窗的空草稿。
    ///
    /// **自己的状态一律在会抛的那步成功之后才清**。放在前面的话：
    /// `commit` 抛错（磁盘满、I/O 错）→ `DraftStore` 回滚，草稿还活着、账本没记；
    /// 而这里已经把 `draft` 置 nil、`isRunning` 置 false。此后用户再按「结束」，
    /// `guard let draft else { return nil }` **静默什么都不做**，
    /// 而 `heartbeatIfNeeded` 也因为 `isRunning` 为假不再打心跳——
    /// 草稿的 `updatedAt` 就此定格，崩溃恢复只能按那一刻估时长，**少记**。
    /// 保持状态不动，用户可以直接再按一次「结束」重试。
    @discardableResult
    func finish(at now: Date = Date()) throws -> PracticeSession? {
        guard let draft else { return nil }
        refresh(at: now)

        guard elapsed > 0 else {
            try drafts.discard(draft)
            self.draft = nil
            isRunning = false
            startedAt = nil
            elapsed = 0
            return nil
        }

        let seconds = elapsed
        let session = try drafts.commit(
            draft, item: item, amount: seconds,
            at: now, dayStartHour: dayStartHour, timeZone: timeZone
        )
        self.draft = nil
        isRunning = false
        if session.dayKey != committedDayKey {
            // 坐过了零点：这一坐落在新的一天，旧那天的 `committedTotal` 跟它没关系，
            // 累加上去屏幕就会替用户多报一整天（3600 + 1800 = 5400，而「今日」只有 1800）。
            //
            // 归零而不是重读账本——重读要 fetch，而这里已经在 commit 成功**之后**，
            // 那次 fetch 抛错会让用户读到「记录失败」，可账其实记上了，那是更坏的谎。
            // 归零的代价是新那天若已有别处记的流水会漏报，方向是「丢」不是「多」，
            // 且下次 `start()`（Task 16 回到前台就调）一次就补齐。
            committedDayKey = session.dayKey
            committedTotal = 0
        }
        // 已经入账，从「本次」挪到「今日已记」。
        // 不挪的话，同一页再坐第二轮时 dayTotal 会把第一轮漏掉。
        committedTotal += seconds
        startedAt = nil
        elapsed = 0
        return session
    }

    /// 放弃本次：草稿与账本都不留痕。
    /// 同样，`discard` 成功之后才清自己的状态——抢在前面清的话，`discard` 抛错时
    /// 屏幕已经归零、`draft` 也指不回去，而那份草稿还躺在盘上，
    /// 下次启动照样弹恢复窗，问用户要不要记上他明明放弃了的那一坐。
    func abandon() throws {
        guard let draft else { return }
        try drafts.discard(draft)
        self.draft = nil
        isRunning = false
        startedAt = nil
        elapsed = 0
    }
}
