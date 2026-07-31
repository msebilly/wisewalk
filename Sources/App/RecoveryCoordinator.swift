import Foundation
import SwiftData
import Observation

/// 一份待用户裁决的草稿。
struct PendingRecovery: Identifiable, Equatable {
    /// 即草稿的 `sessionID`。**不要用 `SessionDraft.id`**——
    /// `@Model` 的 `id` 是 `PersistentIdentifier` 而不是 UUID，
    /// 而 `sessionID` 恰好既唯一、又是入账时要用的那个幂等键。
    let id: UUID
    let itemID: UUID
    let itemName: String
    let source: SessionSource
    let suggestedAmount: Int
    let amountText: String
    let startedAt: Date
    /// 这一坐的**收坐时刻**，也就是草稿最后一次心跳落盘的时刻。
    ///
    /// 它不是给排序用的，是给用户看的：`accept` 拿它算这笔落在哪天
    /// （`at: draft.updatedAt`），所以弹窗必须把它说出来。
    /// 弹窗承诺的和 `accept` 做的，得是同一件事。
    let endedAt: Date
}

enum RecoveryError: LocalizedError {
    /// 草稿指着的那门功课当下查不到。第 3 卷同步只到一半时够得着。
    case itemNotFound(name: String)

    var errorDescription: String? {
        switch self {
        case .itemNotFound(let name):
            return "暂时找不到「\(name)」这门定课，这一笔还没记上。等资料同步好了再试一次。"
        }
    }
}

/// §4.5 第 3 条：启动时的草稿清算。
///
/// **顺序即全部要害**：
/// 1. 先清账——凡 `sessionID` 已入账的草稿一律**静默丢弃**，一个字也不对用户说。
///    「写流水 + 删草稿」那次 `save()` 跨两个 store 文件，本就没有分布式事务；
///    流水落了而草稿没删掉时若去问用户「要恢复这 108 声吗」，点确认就记了两遍，
///    正是 §4.5 要根除的重复写入。
/// 2. 再过滤——点开计数器又立刻退出留下的空草稿，不值得打扰任何人。
/// 3. 剩下的才弹窗。
///
/// **必须在用户能进计时器之前跑完**：否则用户点进打坐页，
/// `TimerViewModel.start()` 会承接那份三天前的草稿接着计时。
@MainActor
@Observable
final class RecoveryCoordinator {
    private(set) var pending: [PendingRecovery] = []
    private(set) var didRun = false

    @ObservationIgnored private let env: AppEnvironment
    @ObservationIgnored private var drafts: [UUID: SessionDraft] = [:]

    init(env: AppEnvironment) {
        self.env = env
    }

    /// **不收 `now`。** 这个函数一次都没问过「现在几点」——它只做对账、过滤、丢弃，
    /// 三件事全靠草稿自己的 `startedAt` / `updatedAt`。带一个从不读的 `Date` 参数
    /// 会让读的人以为「启动清算」跟当下时刻有关，然后照着这个错觉去改。
    func runAtLaunch() throws {
        let live = try env.drafts.reconcilePendingDrafts()

        var result: [PendingRecovery] = []
        var lookup: [UUID: SessionDraft] = [:]
        var orphans: [SessionDraft] = []

        for draft in live {
            // 认不出归属的草稿没法问用户「要恢复吗」——问了他也不知道那是什么。
            // 归档的项仍要问：归档只是不再出现在今日，不是没做过。
            guard let item = try env.items.item(id: draft.itemID) else {
                orphans.append(draft)
                continue
            }
            // 量法改过之后，旧草稿的 amount 与 startedAt 在新量法下每个字段都是错的。
            // `DraftStore.begin` 挡的是「用户又进了计数器」，这里挡「用户重启了 App」。
            guard DraftRecovery.matches(source: draft.source,
                                        measureType: item.measureType) else {
                orphans.append(draft)
                continue
            }
            guard DraftRecovery.isWorthRestoring(
                source: draft.source, amount: draft.amount,
                startedAt: draft.startedAt, updatedAt: draft.updatedAt
            ) else {
                orphans.append(draft)
                continue
            }
            let amount = DraftRecovery.suggestedAmount(
                source: draft.source, amount: draft.amount,
                startedAt: draft.startedAt, updatedAt: draft.updatedAt
            )
            lookup[draft.sessionID] = draft
            result.append(PendingRecovery(
                id: draft.sessionID,
                itemID: item.id,
                itemName: item.name,
                source: draft.source,
                suggestedAmount: amount,
                amountText: text(amount, item: item),
                startedAt: draft.startedAt,
                endedAt: draft.updatedAt
            ))
        }

        // 不值得问的一律清掉。留着的话每次启动都要重新走一遍，越积越多。
        //
        // ⚠️ 已知取舍：`isWorthRestoring` 是个 `Bool`，表达不了第三种状态。
        // 计时草稿在 `updatedAt < startedAt`（时钟回拨）时，`suggestedAmount` 返回 0,
        // 与「这段本来就是空的」撞在一起，于是一段真打过的坐会**无声无息地**被 discard 掉。
        // 这是本卷**两处**会不告诉用户就毁掉数据的地方之一。另一处是
        // `TimerViewModel.finish()` 的 `guard elapsed > 0 else { discard }`——
        // 同一个根因（时钟回拨让挂钟差值变负），但那一处**够到它甚至不需要崩溃**：
        // 坐着的时候表被拨回去，按「结束」就把真坐的半小时连同唯一的恢复凭据
        // 一起销毁了。这里至少还要求「崩在按结束之前」。
        //
        // 没在这一卷修，理由是三条都得成立才踩得到：时钟向后跳**超过**已计时长
        //（iOS 的 NTP 校正是亚秒级，够得上的只有手动改表）、且崩在用户点「结束」之前、
        // 且草稿活到了下次启动。而且同一个根因在实时显示上已经先坏了（见
        // `TimerViewModel.refresh` 的注释），单修恢复这一侧并不自洽。
        //
        // 真要修，根在 Task 10 的计时口径而不在这里：把已计秒数写进草稿的 `amount`，
        // 恢复就不再依赖两个时间戳的差。**在那之前不要**把这里改成「留着不删」——
        // 一份永远算不出时长的草稿会每次启动都来问一遍，那比丢掉更糟。
        for draft in orphans {
            try env.drafts.discard(draft)
        }

        drafts = lookup
        pending = result.sorted { ($0.startedAt, $0.id.uuidString) < ($1.startedAt, $1.id.uuidString) }
        didRun = true
    }

    /// 记上。**用草稿自己的 `sessionID`**——弹窗点两下、或恢复到一半又崩，
    /// `DayLedger.record` 的 id 幂等会挡住第二笔。
    /// 接受这份草稿，把它记进账本。
    ///
    /// **落哪天按草稿的 `updatedAt` 算，不是按用户点头那一刻算。**
    /// 从前传的是 `Date()`，于是昨晚的早课草稿在今早启动时被点了「记上」，
    /// 就记到今天头上——昨天平白少一门功课、今天平白多一门。两个方向都占。
    /// Task 10 自己立的规矩是「落哪天按收坐那一刻算」，而恢复的「收坐那一刻」
    /// 就是心跳最后一次落盘的时刻，也就是 `updatedAt`；用户点头的时刻
    /// 与这一坐发生在什么时候毫无关系。
    ///
    /// `endedAt` 一并跟着走：记「昨晚 21:40 结束」比记「今早 7:02 结束」诚实，
    /// 而且第 5 卷的月历、连续天数全都读的是 dayKey。
    /// **`dayStartHour` 直接从 `env.settings` 读，不做成参数。**
    /// `AppSettings.dayStartHour` 的文档注释白纸黑字写着这条：那一批 `= 0` 的默认值
    /// 「漏传一处，那一处就静默退回 0 点，而没有任何测试会红」。
    /// 这条路上漏传的代价最大——它是**永久写进账本**的一笔，而且是用户看不见的一笔
    /// （他只按了「记上」，不会去核对落在哪天）。设 4 点起始的人正是夜课那批人，
    /// 恰好也是最容易崩在半夜留下草稿的那批人：凌晨 1:30 的早课会被记到第二天，
    /// 昨天平白少一门、今天平白多一门——与「按点头那一刻算」是同一个 bug 的第二个入口。
    ///
    /// `RecoveryCoordinator` 手里就攥着 `env`，没有任何理由让调用方替它转交。
    /// `timeZone` 仍留作参数：它没有对应的用户设置，`.current` 就是生产时的真值，
    /// 而测试必须能注入固定时区（否则断言的尺子和实现是同一把）。
    func accept(_ item: PendingRecovery, timeZone: TimeZone = .current) throws {
        // 草稿不在手里了：这一份已经被处理过（同一份被点了两次、
        // 或上一轮 commit 之后 UI 又回调了一次）。**静默放行是对的**——
        // 该记的已经记了，再说什么都只会让人以为要记两笔。
        guard let draft = drafts[item.id] else {
            pending.removeAll { $0.id == item.id }
            return
        }
        // ⛔ 但「查不到那门功课」完全是另一回事，**不许跟上面走同一条路**。
        // 从前两个条件并在一个 guard 里，查不到功课时把这一份从 pending 里抹掉就返回:
        // 用户按了「记上」，屏幕上弹窗消失、什么都没发生、一个字也没说。
        // 而草稿还躺在盘上——
        //
        //   他以为没记上 → 照着记忆手动补记一遍 → 下次启动弹窗又问同一份 →
        //   他再按一次「记上」→ **这 108 声进了两回账**。
        //
        // 静默的空操作在这里是「多」的源头，不是保守的那一侧。
        // 抛出去让界面说话，pending **留着**，等同步补齐了还能再点一次。
        guard let practiceItem = try env.items.item(id: item.itemID) else {
            throw RecoveryError.itemNotFound(name: item.itemName)
        }
        _ = try env.drafts.commit(draft, item: practiceItem, amount: item.suggestedAmount,
                                  at: draft.updatedAt,
                                  dayStartHour: env.settings.dayStartHour, timeZone: timeZone)
        drafts[item.id] = nil
        pending.removeAll { $0.id == item.id }
    }

    func discard(_ item: PendingRecovery) throws {
        if let draft = drafts[item.id] {
            try env.drafts.discard(draft)
        }
        drafts[item.id] = nil
        pending.removeAll { $0.id == item.id }
    }

    private func text(_ amount: Int, item: PracticeItem) -> String {
        switch item.measureType {
        case .duration: DurationFormat.spoken(amount)
        case .check: "已完成"
        case .count: item.unit.isEmpty ? "\(amount)" : "\(amount) \(item.unit)"
        }
    }
}
