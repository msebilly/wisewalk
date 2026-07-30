import Foundation
import Observation

enum ManualEntryError: Error, Equatable {
    case noItemSelected
    case nonPositiveAmount
    /// 明天的功课还没做。
    case futureDay
}

/// 手动补记与修正。
///
/// §6.4 明确这是**并列的第三种录入方式，不是次要功能**——
/// 很多人修完才想起来记；而竞品差评证明「改错数字找不到入口」是真实痛点，
/// 所以修正入口必须显眼。
@MainActor
@Observable
final class ManualEntryViewModel {
    /// §6.12 迁移：把纸本或别家 App 的历史累计一次性记成一笔时打的固定备注。
    /// 第 3 卷诊断页据此把它与日常流水区分开——否则「累计 30 万声」里
    /// 那笔 29 万的起始数会让日均统计毫无意义。
    static let migrationNote = "migration:initial-total"

    var selectedItem: PracticeItem?
    var selectedDayKey: Int = 0
    /// 计数类为遍数，计时类为**秒**。
    var amount: Int = 0
    var note: String = ""

    private let ledger: DayLedger
    private let items: PracticeItemStore

    init(ledger: DayLedger, items: PracticeItemStore) {
        self.ledger = ledger
        self.items = items
    }

    /// 提交按钮亮不亮。
    ///
    /// **「今天」由自己算，与 `submit` 走同一条路**。从前是让调用方传现成的
    /// `today: Int` 进来，那就等于同一份设置被两个方法各收了一份——
    /// 传的那个若用了别的 `dayStartHour` 或时区，按钮亮着而 `submit` 抛
    /// `.futureDay`，用户点下去只看到一句「出了点问题」。
    /// 这个形状在 `CounterViewModel` 与 `TimerViewModel` 上已经各栽过一次。
    func canSubmit(at now: Date = Date(), dayStartHour: Int = 0,
                   timeZone: TimeZone = .current) -> Bool {
        guard selectedItem != nil, amount > 0 else { return false }
        let today = DayKey.today(dayStartHour: dayStartHour, now: now, timeZone: timeZone)
        return !DayKey.isFuture(selectedDayKey, comparedTo: today)
    }

    /// 补记一笔。
    ///
    /// 三个时间刻意不一致，这正是 `record(onDay:)` 存在的理由：
    /// - `dayKey` 是**所选日期**（功课发生在哪天）
    /// - `createdAt` 是**真实写入时刻**（这条何时写下）
    /// - `tzOffsetMinutes` 是**当前**偏移
    ///
    /// 若靠回拨 `at:` 来补记，会连带篡改 `createdAt`（快照去重排序与第 3 卷诊断都依赖它）
    /// 和历史时区偏移，让「这条何时写下」永远说不清。
    @discardableResult
    func submit(
        at now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current
    ) throws -> PracticeSession {
        try submit(note: trimmedNote, at: now, dayStartHour: dayStartHour, timeZone: timeZone)
    }

    /// §6.12 迁移入口：把历史累计记成一笔起始流水。
    ///
    /// **固定备注会盖掉用户自己写的 `note`**——这是有意的：这笔的备注是给程序看的
    /// 幂等/识别标记，不是给人看的文字。Task 17 的迁移表单不该出现备注输入框。
    @discardableResult
    func submitMigrationTotal(
        at now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current
    ) throws -> PracticeSession {
        try submit(note: Self.migrationNote, at: now, dayStartHour: dayStartHour, timeZone: timeZone)
    }

    private func submit(
        note: String?,
        at now: Date,
        dayStartHour: Int,
        timeZone: TimeZone
    ) throws -> PracticeSession {
        guard let item = selectedItem else { throw ManualEntryError.noItemSelected }
        guard self.amount > 0 else { throw ManualEntryError.nonPositiveAmount }
        // **把校验过的数抄成局部量再往下走。**
        // 从前底下那句 `record` 直接读 `self.amount`，于是「校验的是哪个数」
        // 与「记进账本的是哪个数」中间隔着两次会抛的 I/O，全靠「这中间没人改它」
        // 这个默契撑着——而这份默契在代码里一个字都没写。
        // Step 9 变异 3 一挪清空的位置，`record` 当场收到 0：证据就在那儿。
        // 这是个只增不减的账本，往里写的那个数不该是可变状态的即时读数。
        let amount = self.amount
        let today = DayKey.today(dayStartHour: dayStartHour, now: now, timeZone: timeZone)
        guard !DayKey.isFuture(selectedDayKey, comparedTo: today) else {
            throw ManualEntryError.futureDay
        }

        // §6.4：补记历史日期时，若该日快照不存在则按当日配置补建；已存在则沿用，绝不覆盖。
        // 不补建的话，第 5 卷月历翻到那天会显示「无课」，而明明记着 500 声。
        // `plan(for:activeItems:)` 本身就是「没有才建、有了不动」，直接调即可。
        //
        // ⚠️ **这是 `docs/design-spec.md` §5.6 那个问题的第二个写侧入口**（第一个是
        // `TodayViewModel.reload`）。换新机后 CloudKit 只同步到一半时补记一笔历史，
        // 就会拿**此刻本机看得见的**定课集合给那一天永久定格快照——
        // 而「已存在则沿用、绝不覆盖」意味着**再也改不回来**。
        // 第 3 卷开真实同步之前必须先答 §5.6 的三个问题，答完回来看这里。
        //
        // ⚠️ 还有一层：这一句**自己会 save**。它成功之后 `record` 若抛错（磁盘满等），
        // 库里就留下一个「有快照、一笔流水都没有」的历史日——第 5 卷月历翻到那天
        // 会说「这几门功课你一门都没做」，而用户那天可能压根还没建这些功课。
        // **编一个失败比说「无课」更糟。** 用户重新补记一次会自愈（快照沿用、流水补上）。
        // 没在这一卷动它，是因为把两次 save 合成一次要改第一卷已封存的 `DayLedger`。
        _ = try ledger.plan(for: selectedDayKey, activeItems: try items.activeItems())

        let session = try ledger.record(
            item: item,
            amount: amount,
            source: .manual,
            startedAt: now,
            endedAt: now,
            at: now,
            dayStartHour: dayStartHour,
            timeZone: timeZone,
            note: note,
            onDay: selectedDayKey
        )
        // **记上了就把数清掉。** 计数器与计时器靠草稿的 `sessionID` 查重，
        // 连点两下、崩溃重放都只会记一笔；补记这条路一份草稿都没有，
        // `record` 每次都新生成一个 id，**没有任何东西拦得住第二次提交**。
        // 用户手快点两下就是 1000 声，而他补记的是 500——正顶着「一声都不能多」。
        // 清空之后第二次提交撞 `.nonPositiveAmount`，什么都不会写。
        //
        // 清在 `record` 成功**之后**（纪律第 6 条）：抢在前面清的话，
        // 磁盘满导致 `record` 抛错时，用户填的数已经没了，得重打一遍。
        self.amount = 0
        self.note = ""
        return session
    }

    /// 修正：追加一笔等额负数，**原记录纹丝不动**。
    /// `DayLedger.revoke` 以 `note` 里的 `revoke:<原记录 id>` 为幂等键，
    /// 用户手快点两下、或两台设备各撤一次，都只会扣一次。
    ///
    /// **不收时区**：撤销落在哪天与时区毫无关系，那笔负数的 `dayKey` 与
    /// `tzOffsetMinutes` 一律照抄**原流水**的。今天撤销七月一日的一笔，
    /// 负数就落在七月一日。从前这里收一个 `timeZone` 再原样传下去，
    /// 而 `DayLedger.revoke` 根本不看它——一个只会让人误以为「时区影响落日」的死参数。
    ///
    /// ⚠️ 谁要是把落日改成按「现在」推，七月一日会照旧记着 5000、今天凭空多出 −5000，
    /// 两天同时说谎；而 `total` 的 clamp 还会把今天那笔掩盖成「归零」，
    /// 用户今天真做过的功课就此凭空消失。`撤销历史流水负数落在功课那天而不是今天`
    /// 这条测试守的就是这个。
    func revoke(_ session: PracticeSession, at now: Date = Date()) throws {
        try ledger.revoke(session, at: now)
    }

    /// 某天某项的全部流水，**最近写的排在最前**——用户要改的多半是刚记错的那笔。
    func entries(on dayKey: Int, itemID: UUID) throws -> [PracticeSession] {
        try ledger.sessions(on: dayKey, itemID: itemID).sorted {
            ($0.createdAt, $0.id.uuidString) > ($1.createdAt, $1.id.uuidString)
        }
    }

    private var trimmedNote: String? {
        let t = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
