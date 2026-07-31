import Testing
import SwiftData
import Foundation
@testable import WiseWalk

/// §5.6 写侧定案的守卫：同步迟到的定课要能补回当日应做，
/// 而今天新立的课不许溜进今天。
///
/// 这一组全部用**固定时区 + 固定时刻**，不碰 `.current`、不碰 `Date()`。
/// 本机是 PDT，本卷已经两次因为跟着系统时区跑而假绿。
@MainActor
private func 建() throws -> (DayLedger, ModelContext) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    return (DayLedger(context: ctx, deviceName: "iPhone·TEST"), ctx)
}

private let 北京 = TimeZone(identifier: "Asia/Shanghai")!

private func 时刻(_ mo: Int, _ d: Int, _ h: Int) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = mo; c.day = d; c.hour = h
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = 北京
    return cal.date(from: c)!
}

private func 课(_ name: String, 立于 born: Date, 目标 goal: Int? = nil, 归档 archived: Bool = false) -> PracticeItem {
    let it = PracticeItem(name: name, dailyGoal: goal, createdAt: born)
    it.isArchived = archived
    return it
}

@Test @MainActor func 迟到的定课会被追加进当日应做() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    let 打坐 = 课("打坐", 立于: 时刻(7, 22, 9))
    ctx.insert(念佛); ctx.insert(打坐)

    // 只有念佛在场时先把 7/28 定格了。
    let 初 = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    #expect(初.requiredItemIDs == [念佛.id])

    // 打坐随后同步进来——它 7/22 就立了，7/28 那天本来就该在。
    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)
    #expect(Set(后.requiredItemIDs) == Set([念佛.id, 打坐.id]))
}

@Test @MainActor func 今天新立的定课不会被追加进今天() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    let 诵经 = 课("诵经", 立于: 时刻(7, 28, 15))   // 就是当天下午立的
    ctx.insert(念佛); ctx.insert(诵经)

    _ = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 诵经], dayStartHour: 0, timeZone: 北京)

    // 下午才立的课不该被追加进上午已经定格好的今天——
    // 那等于让「上午已显示圆满」的一天因为下午添了门功课而退回未圆满。
    // 注意这与初次定格**不对称**（见 `appendLateArrivals` 的注释）：
    // 该日尚无快照时，今天刚立的课是照收的。
    #expect(后.requiredItemIDs == [念佛.id])
}

@Test @MainActor func 没有迟到项时一条快照都不多写() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    ctx.insert(念佛)

    _ = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    for _ in 0..<5 {
        _ = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    }

    // 另开一个**同容器**的 context 才问得出「盘上到底有几条」：
    // `FetchDescriptor.includePendingChanges` 默认 true，同一个 ctx 上查会把未落盘的
    // insert 也算进去，证明不了任何事。注意不能用 `ModelContainerFactory.inMemory()`——
    // 那是**另造一个容器**，跟 ctx 毫无关系，查出来永远是 0。
    let 盘上 = ModelContext(ctx.container)
    #expect(try 盘上.fetch(FetchDescriptor<DaySnapshot>()).count == 1)
}

@Test @MainActor func 追加过一次就不会再追加() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    let 打坐 = 课("打坐", 立于: 时刻(7, 22, 9))
    ctx.insert(念佛); ctx.insert(打坐)

    let 初 = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    #expect(初.requiredItemIDs == [念佛.id], "定格这步得真把念佛记下，否则下面数出的 2 条说明不了问题")
    _ = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)
    _ = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)

    // 初次一条 + 追加一条 = 两条。第三次调用不该再添。
    // 同样要问同容器的另一个 context，否则「只 insert 没 save」也会被算成落了盘。
    #expect(try ModelContext(ctx.container).fetch(FetchDescriptor<DaySnapshot>()).count == 2)
}

@Test @MainActor func 已归档的迟到定课不会被追加() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    let 旧课 = 课("旧课", 立于: 时刻(7, 1, 9), 归档: true)
    ctx.insert(念佛); ctx.insert(旧课)

    _ = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 旧课], dayStartHour: 0, timeZone: 北京)
    #expect(后.requiredItemIDs == [念佛.id])
}

@Test @MainActor func 追加项的目标取自追加时那条快照() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9), 目标: 1000)
    let 打坐 = 课("打坐", 立于: 时刻(7, 22, 9), 目标: 30)
    ctx.insert(念佛); ctx.insert(打坐)

    _ = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)

    // 最早那条快照对打坐毫无意见，故取「含它的最早一条」——就是追加的这条。
    #expect(后.goals[打坐.id.uuidString] == 30)
    #expect(后.goals[念佛.id.uuidString] == 1000)
}

@Test @MainActor func 初次定格仍旧收下全部在册定课() throws {
    let (ledger, ctx) = try 建()
    // 用户今天装了 App，今天立的课，补记三天前。
    let 念佛 = 课("念佛", 立于: 时刻(7, 28, 10))
    ctx.insert(念佛)

    let 计划 = try ledger.plan(for: 20260725, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)

    // **activatedAt 判据只管追加，绝不能套到初次定格上。**
    // 套上去的话，新用户补录过去三十天会得到三十条空快照，
    // 每一天都记着几百声却显示「无课」——正是 §5.6 要治的那个病，反倒被治法造出来。
    #expect(计划.requiredItemIDs == [念佛.id])
}

@Test @MainActor func 空快照的一天在定课同步进来后能自愈() throws {
    let (ledger, ctx) = try 建()
    // 换新机首启：一条定课都还没推下来。
    let 空 = try ledger.plan(for: 20260728, activeItems: [], dayStartHour: 0, timeZone: 北京)
    #expect(空.requiredItemIDs.isEmpty)

    let 全 = (1...3).map { 课("第\($0)门", 立于: 时刻(7, 10, 9)) }
    for it in 全 { ctx.insert(it) }

    let 愈 = try ledger.plan(for: 20260728, activeItems: 全, dayStartHour: 0, timeZone: 北京)
    #expect(Set(愈.requiredItemIDs) == Set(全.map(\.id)), "补回来的得正是这三门，不能只是凑够个数")
}

@Test @MainActor func 装上头一天立的第一门课当天就得能记() throws {
    // ⛔ **这条是 2026-07-31 在模拟器里手点出来的，361 条测试全绿。**
    //
    // 新用户的必然路径，一步不多：
    //   1. 装好 App 打开 → 今日页一露面就调 `plan` → 那天还没有快照 →
    //      初次定格，收下「全部在册定课」＝ **空** → 落一条空快照
    //   2. 他点「立一门定课」立了第一门 → `activatedAt` ＝ 今天
    //   3. 回到今日页 → 那天**已有**快照 → 走 `appendLateArrivals` →
    //      `activeSince < dayKey` 把今天立的挡在外面 → 今日页仍是空态
    //
    // 后果不是「圆满被夺」那一档，是**更基础的失败：他今天根本记不了**。
    // 计数器和计时器的入口只在今日页的功课行上，行不出现就点不进去。
    // 一个刚请回来的 App，头一天立的头一门课，当天不认。
    //
    // 现场证据（模拟器 SQLite）：空快照 15:52:35 定格，定课 15:57:18 立，差 4 分 43 秒。
    //
    // §5.6 那段注释写着「接受它，是因为初次定格只在该日尚无任何快照时触发，
    // **那一刻没有圆满可夺**」——那句话本身对，但它把代价算小了：
    // 那一刻确实没有圆满可夺（他一门课都没有），可代价不是圆满，是**当天的入口**。
    //
    // 判据只放宽在「已有快照全都是空的」这一处：
    // 空快照说明定格那一刻他一门课都没有，那天没有任何圆满可言，
    // 重新收全部在册定课不从任何人手里拿走东西——
    // 与 `初次定格` 那个分支问的是同一句话，答案自然也该一样。
    let (ledger, ctx) = try 建()

    // 1. 今日页一露面，一门课都没有
    let 空 = try ledger.plan(for: 20260728, activeItems: [], dayStartHour: 0, timeZone: 北京)
    #expect(空.requiredItemIDs.isEmpty)

    // 2. 他立了第一门课，就在今天
    let 念佛 = 课("念佛", 立于: 时刻(7, 28, 10), 目标: 1000)
    ctx.insert(念佛)

    // 3. 回今日页
    let 再 = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    #expect(再.requiredItemIDs == [念佛.id], "头一天立的头一门课，今日页上必须有它")
    #expect(再.goals[念佛.id.uuidString] == 1000, "目标也要跟着进来，否则圆满没有分母")
}

@Test @MainActor func 已经有课的那天新立的课仍旧不算今天() throws {
    // 上一条只放宽「空快照」这一处，**不许顺手把不对称修平**。
    // 已经有课的那天，下午新立一门课不能追加进来——
    // 上午已经显示圆满的那半天会因此退回未圆满，那是替他改写已经过完的时间。
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    ctx.insert(念佛)
    let 初 = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    #expect(初.requiredItemIDs == [念佛.id])

    let 打坐 = 课("打坐", 立于: 时刻(7, 28, 15))
    ctx.insert(打坐)
    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)
    #expect(后.requiredItemIDs == [念佛.id], "那天已经有课了，今天下午新立的不算今天")
}

@Test @MainActor func 今天恢复的归档定课不会被追加进今天() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    let 打坐 = 课("打坐", 立于: 时刻(7, 1, 9), 归档: true)
    ctx.insert(念佛); ctx.insert(打坐)

    // 早上定格时打坐还归着，不在快照里。
    let 初 = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    #expect(初.requiredItemIDs == [念佛.id], "定格得真发生过；空快照会让打坐从追加路径混进来，这条就白守了")

    // 下午才恢复。追加进今天就等于把他今天已经挣到的圆满收回去。
    try PracticeItemStore(context: ctx).unarchive(打坐, at: 时刻(7, 28, 15))
    #expect(打坐.isArchived == false, "恢复得真成功；没恢复的话它会被 !isArchived 挡掉，这条就为错误的原因通过了")

    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)
    #expect(后.requiredItemIDs == [念佛.id])
}

@Test @MainActor func 对本来就活着的课调恢复不会顶掉它的激活时刻() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    let 打坐 = 课("打坐", 立于: 时刻(7, 22, 9))
    ctx.insert(念佛); ctx.insert(打坐)

    let 初 = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    #expect(初.requiredItemIDs == [念佛.id])

    // 打坐从没归档过。UI 上一个按钮连点两下、或列表刷新重放一次动作就会这样调。
    // `unarchive` 若不先看它归没归着就改 `activatedAt`，这门 7/22 就立好的课
    // 会被判成「今天才激活」，从此再也补不回 7/28——方向是「多」，替用户免掉一门。
    try PracticeItemStore(context: ctx).unarchive(打坐, at: 时刻(7, 28, 15))

    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)
    #expect(Set(后.requiredItemIDs) == Set([念佛.id, 打坐.id]))
}

@Test @MainActor func 昨天恢复的归档定课同步进来后仍要被追加() throws {
    let (ledger, ctx) = try 建()
    let 念佛 = 课("念佛", 立于: 时刻(7, 20, 9))
    let 打坐 = 课("打坐", 立于: 时刻(7, 1, 9), 归档: true)
    ctx.insert(念佛); ctx.insert(打坐)

    let 初 = try ledger.plan(for: 20260728, activeItems: [念佛], dayStartHour: 0, timeZone: 北京)
    #expect(初.requiredItemIDs == [念佛.id], "定格得真发生过，否则打坐是被「整体重建」加回来的，不是被追加的")

    // 昨晚就在 iPad 上恢复了，今天本机才同步到——那时它确实是今天该做的。
    // 这一条与上一条只差在「恢复发生在哪一天」，正是 activatedAt 记的东西。
    try PracticeItemStore(context: ctx).unarchive(打坐, at: 时刻(7, 27, 21))
    #expect(打坐.isArchived == false, "恢复得真成功，否则它连 !isArchived 那一关都过不去")

    let 后 = try ledger.plan(for: 20260728, activeItems: [念佛, 打坐], dayStartHour: 0, timeZone: 北京)
    #expect(Set(后.requiredItemIDs) == Set([念佛.id, 打坐.id]))
}
