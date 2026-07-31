import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeLedger() throws -> (DayLedger, ModelContext, PracticeItem) {
    let container = try ModelContainerFactory.inMemory()
    let ctx = ModelContext(container)
    let item = PracticeItem(name: "念佛", measureType: .count, unit: "声", dailyGoal: 1000)
    ctx.insert(item)
    try ctx.save()
    return (DayLedger(context: ctx, deviceName: "iPhone·TEST"), ctx, item)
}

private let 北京时间 = TimeZone(identifier: "Asia/Shanghai")!

private func 北京(_ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
    var c = DateComponents()
    c.year = 2026; c.month = mo; c.day = d; c.hour = h; c.minute = mi
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = 北京时间
    return cal.date(from: c)!
}

@MainActor
@Test func 记一笔后可以查到() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
}

@MainActor
@Test func 多笔累加() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    for amount in [108, 500, 21] {
        try ledger.record(item: item, amount: amount, source: .counter,
                          startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    }
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 629)
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).count == 3)
}

@MainActor
@Test func 撤销是追加负数而非删除() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let original = try ledger.record(item: item, amount: 500, source: .counter,
                                     startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    try ledger.revoke(original, at: now, timeZone: 北京时间)

    let all = try ledger.sessions(on: 20260728, itemID: item.id)
    #expect(all.count == 2, "原记录必须还在，撤销是追加一笔而不是删除")
    #expect(all.contains { $0.id == original.id }, "原记录被删掉了")
    #expect(all.contains { $0.amount == -500 && $0.source == .adjustment })
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func 撤销笔记指向原记录() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let original = try ledger.record(item: item, amount: 500, source: .counter,
                                     startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    let adj = try ledger.revoke(original, at: now, timeZone: 北京时间)
    #expect(adj.note == "revoke:\(original.id.uuidString)")
}

@MainActor
@Test func 重复撤销同一笔只记一次() throws {
    // 崩溃重放或多设备同撤：同一笔的 -amount 只能追加一次。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let a = try ledger.record(item: item, amount: 500, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    try ledger.revoke(a, at: now, timeZone: 北京时间)
    try ledger.revoke(a, at: now, timeZone: 北京时间)

    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == 0, "第二次撤销必须被幂等吞掉")
    let adjustments = try ledger.sessions(on: 20260728, itemID: item.id)
        .filter { $0.source == .adjustment }
    #expect(adjustments.count == 1, "同一笔撤销只应留下一条 .adjustment")
}

@MainActor
@Test func 撤销不会波及同日其他流水() throws {
    // 本 finding 的回归测试：S1、S2 是两笔独立真实修行。
    // 重复撤销 S1 若不幂等，第二笔 -500 会先吃掉 S2 的 300，再被 clamp 掩盖，
    // 显示归零看似合理，实则凭空抹掉了真做过的 300 声。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let s1 = try ledger.record(item: item, amount: 500, source: .counter,
                               startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    try ledger.record(item: item, amount: 300, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    try ledger.revoke(s1, at: now, timeZone: 北京时间)
    try ledger.revoke(s1, at: now, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 300,
            "重复撤销不得吃掉另一笔真实修行")
}

@MainActor
@Test func 孤立的负数调整不被存储层掩盖() throws {
    // 同步偏序：撤销这笔 .adjustment 先于它的原始正记录抵达本机，
    // 此刻账本原值理应为负。rawTotal 必须如实暴露，好让同步 bug 看得见；
    // 只有显示层 displayTotal 才 clamp 到 0。
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let orphan = PracticeSession(
        item: item,
        dayKey: 20260728,
        tzOffsetMinutes: 480,
        amount: -500,
        startedAt: now,
        endedAt: now,
        source: .adjustment,
        deviceName: "iPad·TEST",
        note: "revoke:\(UUID().uuidString)",
        createdAt: now
    )
    ctx.insert(orphan)
    try ctx.save()

    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == -500, "账本原值必须如实为负")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0, "显示层 clamp 到 0")
}

@MainActor
@Test func 记录自动带上日期键与时区() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 23, 30)
    let s = try ledger.record(item: item, amount: 1, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    #expect(s.dayKey == 20260728)
    #expect(s.tzOffsetMinutes == 480)
    #expect(s.deviceName == "iPhone·TEST")
}

@MainActor
@Test func 一日起始为凌晨三点时深夜记录归前一天() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 1, 30)
    let s = try ledger.record(item: item, amount: 1, source: .counter,
                              startedAt: now, endedAt: now, at: now,
                              dayStartHour: 3, timeZone: 北京时间)
    #expect(s.dayKey == 20260727)
}

@MainActor
@Test func 不同天的流水互不干扰() throws {
    let (ledger, _, item) = try makeLedger()
    let d27 = 北京(7, 27, 9, 0)
    let d28 = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 300, source: .counter,
                      startedAt: d27, endedAt: d27, at: d27, timeZone: 北京时间)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: d28, endedAt: d28, at: d28, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260727, itemID: item.id) == 300)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
}

@MainActor
@Test func 不同定课项互不干扰() throws {
    let (ledger, ctx, item) = try makeLedger()
    let other = PracticeItem(name: "持咒", measureType: .count, unit: "遍")
    ctx.insert(other)
    try ctx.save()

    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    try ledger.record(item: other, amount: 21, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
    #expect(try ledger.total(on: 20260728, itemID: other.id) == 21)
}

@MainActor
@Test func 幂等检查能识别已入账的编号() throws {
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let known = UUID()
    #expect(try ledger.exists(sessionID: known) == false)

    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间, id: known)
    #expect(try ledger.exists(sessionID: known) == true)
}

@MainActor
@Test func 同一编号重复入账只记一笔() throws {
    // 崩溃恢复场景：草稿携带预生成编号，恢复时若已入账则不可重复写。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let known = UUID()
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间, id: known)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间, id: known)

    #expect(try ledger.sessions(on: 20260728, itemID: item.id).count == 1)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
}

@MainActor
@Test func 计时类流水以秒记账() throws {
    let (ledger, ctx, _) = try makeLedger()
    let sit = PracticeItem(name: "打坐", measureType: .duration, dailyGoal: 1800)
    ctx.insert(sit)
    try ctx.save()

    let start = 北京(7, 28, 5, 0)
    let end = 北京(7, 28, 5, 45)
    try ledger.record(item: sit, amount: Int(end.timeIntervalSince(start)),
                      source: .timer, startedAt: start, endedAt: end,
                      at: end, timeZone: 北京时间)

    #expect(try ledger.total(on: 20260728, itemID: sit.id) == 2700)
}

@MainActor
@Test func 孤儿流水不计入任何定课项的统计() throws {
    // item == nil 的流水（定课项被硬删后遗留的孤儿）被 sessions(on:itemID:) 里
    // $0.item?.id == itemID 这道过滤挡在所有查询之外：既不出现在任何 sessions 结果，
    // 也不进 total / rawTotal。故 PracticeItem 只能归档（isArchived）、**绝不能硬删**——
    // 一旦硬删，那项的全部历史会从每个统计里凭空蒸发，正是本数据模型要根除的静默丢数。
    // （让孤儿重新现身是第 3 卷诊断的活儿。）
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    // 直接插入一笔孤儿流水（测试夹具，故意绕过 DayLedger 制造 item == nil）。
    let orphan = PracticeSession(
        item: nil,
        dayKey: 20260728,
        tzOffsetMinutes: 480,
        amount: 500,
        startedAt: now,
        endedAt: now,
        source: .manual,
        deviceName: "iPad·TEST",
        createdAt: now
    )
    ctx.insert(orphan)
    try ctx.save()

    // 夹具自检：孤儿确实落库了，测试不是空转。
    #expect(try ctx.fetch(FetchDescriptor<PracticeSession>()).count == 2, "孤儿应已入库")

    let 该项流水 = try ledger.sessions(on: 20260728, itemID: item.id)
    #expect(该项流水.count == 1, "孤儿流水不该出现在任何定课项的 sessions 结果里")
    #expect(该项流水.allSatisfy { $0.id != orphan.id }, "孤儿不该混进该项流水")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108,
            "孤儿的 500 不计入 total，所以 PracticeItem 只能归档不能硬删，否则历史蒸发")
    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == 108,
            "孤儿的 500 也不计入 rawTotal")
}

@MainActor
@Test func 补记到指定日期而写入时间仍为当下() throws {
    // §6.4：dayKey 为所选日期，但 createdAt 必须是真实写入时刻、tzOffsetMinutes 为当前偏移。
    // 「功课发生在哪天」与「这条何时写下」是两件事，不能挤进同一个 at: 参数——
    // 否则补记上周二会连带伪造 createdAt（快照去重排序与第 3 卷诊断都靠它）。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let s = try ledger.record(item: item, amount: 108, source: .manual,
                              startedAt: now, endedAt: now, at: now,
                              timeZone: 北京时间, onDay: 20260721)

    #expect(s.dayKey == 20260721, "应落在所选日期")
    #expect(s.createdAt == now, "createdAt 必须是真实写入时刻，不能被补记日期篡改")
    #expect(s.tzOffsetMinutes == 480, "tzOffsetMinutes 为当前时区偏移")
    #expect(try ledger.total(on: 20260721, itemID: item.id) == 108, "计入所选日期")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0, "不得混进今天的总数")
}

@MainActor
@Test func 不指定补记日期时沿用旧行为() throws {
    // 回归护栏：省略 onDay: 时 dayKey 仍由 at:/dayStartHour/timeZone 推导。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 23, 30)
    let s = try ledger.record(item: item, amount: 1, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    #expect(s.dayKey == 20260728)
    #expect(s.createdAt == now)
}

@MainActor
@Test func stage不落盘而record落盘() throws {
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)

    let staged = try ledger.stage(item: item, amount: 108, source: .counter,
                                  startedAt: now, at: now, timeZone: 北京时间)
    #expect(staged.amount == 108)
    #expect(ctx.hasChanges, "stage 之后应当还有未落盘的改动")

    // 必须另开一个 context 才问得出「进没进 store」：FetchDescriptor.includePendingChanges
    // 默认为 true，同一个 ctx 上查会把未落盘的 insert 也算进去，什么也证明不了。
    #expect(try ModelContext(ctx.container).fetch(FetchDescriptor<PracticeSession>()).isEmpty,
            "stage 只是暂存，别的 context 不该看见这笔")

    try ctx.save()
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
    #expect(try ModelContext(ctx.container).fetch(FetchDescriptor<PracticeSession>()).count == 1,
            "save 之后这笔才真正落进 store")
}

@MainActor
@Test func stage与record查重逻辑一致() throws {
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let id = UUID()

    let first = try ledger.record(item: item, amount: 100, source: .counter,
                                  startedAt: now, at: now, timeZone: 北京时间, id: id)
    let again = try ledger.stage(item: item, amount: 100, source: .counter,
                                 startedAt: now, at: now, timeZone: 北京时间, id: id)
    try ctx.save()

    #expect(first.id == again.id, "stage 必须和 record 命中同一道查重")
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).count == 1, "查重失效，记出了第二笔")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 100)
}

@MainActor
@Test func stage同样支持补记到指定日期() throws {
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    try ledger.stage(item: item, amount: 50, source: .manual,
                     startedAt: now, at: now, timeZone: 北京时间, onDay: 20260701)
    try ctx.save()
    #expect(try ledger.total(on: 20260701, itemID: item.id) == 50)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0)
}

@MainActor
@Test func record仍旧自己落盘不需要调用方再save() throws {
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    try ledger.record(item: item, amount: 7, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间)
    #expect(!ctx.hasChanges, "record 应当已经落盘，不该留下未保存的改动")
}

@MainActor
@Test func 两台设备各撤一次同一笔只扣一次() throws {
    // §5.7。离线时两台设备各撤销同一笔 500，各自查本地都查不到那个幂等键，
    // 于是各建一笔 amount −500、note 同为 "revoke:<同一个 id>"、**但 UUID 不同**
    // 的调整流水。CloudKit 合并后两笔都在库里，就是下面手工造出来的样子。
    //
    // 不去重的话：+500 +300 −500 −500 = −200，`total` clamp 成 0，
    // 用户看到「今天 0 声」——他真念的那 300 声就这么没了，**账面上还看不出哪儿错**。
    // 方向是「丢」，且是最难察觉的一种：没有任何提示，数字只是变小了。
    //
    // 造两条同 note 不同 UUID 的记录直接 insert，不必等真容器。
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let 五百 = try ledger.record(item: item, amount: 500, source: .counter,
                               startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    _ = try ledger.record(item: item, amount: 300, source: .counter,
                          startedAt: now, endedAt: now, at: now, timeZone: 北京时间)

    // 本机撤一次
    _ = try ledger.revoke(五百, at: now, timeZone: 北京时间)
    // 另一台设备离线时也撤了同一笔，同步过来
    let 远端那笔 = PracticeSession(
        item: item, dayKey: 五百.dayKey, tzOffsetMinutes: 五百.tzOffsetMinutes,
        amount: -500, startedAt: now, endedAt: now, source: .adjustment,
        deviceName: "iPad·别人", note: "revoke:\(五百.id.uuidString)", createdAt: now
    )
    ctx.insert(远端那笔)
    try ctx.save()

    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == 300,
            "同一笔只该被撤一次：500 + 300 − 500 = 300")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 300,
            "他真念的那 300 声不能被 clamp 掩盖成 0")
}

@MainActor
@Test func 撤不同的两笔各扣各的() throws {
    // 去重的键是**完整 note 字符串**，不是「note 非空」也不是「同 item 同 amount」。
    // 写松一档就会把两笔撤销塌成一笔——那 500 声凭空回来了，方向是「多」。
    let (ledger, _, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let a = try ledger.record(item: item, amount: 500, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    let b = try ledger.record(item: item, amount: 500, source: .counter,
                              startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    _ = try ledger.revoke(a, at: now, timeZone: 北京时间)
    _ = try ledger.revoke(b, at: now, timeZone: 北京时间)

    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == 0,
            "两笔各撤各的，金额一样也不是同一组")
}

@MainActor
@Test func 重复的撤销笔在流水里也只出现一次() throws {
    // 补记页那列流水读的也是 sessions()。重复那笔留在列表里，
    // 用户会看见两条一模一样的「撤销 −500」，以为自己手滑撤了两次，
    // 转头就去补记页把 500 补回来——那才是真的多记。
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let 五百 = try ledger.record(item: item, amount: 500, source: .counter,
                               startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    _ = try ledger.revoke(五百, at: now, timeZone: 北京时间)
    ctx.insert(PracticeSession(
        item: item, dayKey: 五百.dayKey, tzOffsetMinutes: 五百.tzOffsetMinutes,
        amount: -500, startedAt: now, endedAt: now, source: .adjustment,
        deviceName: "iPad·别人", note: "revoke:\(五百.id.uuidString)", createdAt: now
    ))
    try ctx.save()

    let rows = try ledger.sessions(on: 20260728, itemID: item.id)
    #expect(rows.filter { $0.source == .adjustment }.count == 1,
            "同一笔的两条撤销在列表里只该出现一条")
    #expect(rows.count == 2, "原记录 + 一条撤销")
}

@MainActor
@Test func 重复撤销留下哪一条不许随输入顺序变() throws {
    // §5.7 的次键 `id.uuidString`。我原先把它记成「已知空洞，不补」，
    // 理由是「两条 amount 与 note 必然相同，要钉住它得把实现抄进断言」。
    // **那个理由不完整**：两条重复撤销来自不同设备，`deviceName` 就不同,
    // 而流水页把它显示出来。
    //
    // 没有次键时，`createdAt` 并列的两条谁活下来取决于 `sorted` 收到的输入顺序,
    // 而各设备的 CloudKit 拉取顺序不受任何约束——同一条流水，
    // 这台显示「iPhone·本机」，那台显示「iPad·别人」。
    //
    // 断言写成「换个输入顺序，活下来的还是同一条」，
    // **不抄实现的排序规则**，只钉住它买到的那个性质：结果与输入顺序无关。
    let (_, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    let 被撤的 = UUID()
    func 造(_ 设备: String) -> PracticeSession {
        PracticeSession(item: item, dayKey: 20260728, tzOffsetMinutes: 480,
                        amount: -500, startedAt: now, endedAt: now, source: .adjustment,
                        deviceName: 设备, note: "revoke:\(被撤的.uuidString)", createdAt: now)
    }
    let 甲 = 造("iPhone·本机"), 乙 = 造("iPad·别人")
    ctx.insert(甲); ctx.insert(乙); try ctx.save()

    let 正序 = DayLedger.dedupedRevocations([甲, 乙])
    let 倒序 = DayLedger.dedupedRevocations([乙, 甲])
    #expect(正序.count == 1 && 倒序.count == 1, "两条重复撤销只该活下来一条")
    #expect(正序.first?.deviceName == 倒序.first?.deviceName,
            "活下来的必须是同一条，不许随 CloudKit 的拉取顺序变")
}

@MainActor
@Test func 不带撤销标记的调整笔不参与去重() throws {
    // 去重的两个条件里，「`revoke:` 前缀」这一条今天是为**将来**承重的：
    // `revoke` 是眼下唯一写 .adjustment 的地方，note 全带这个前缀，
    // 所以去掉前缀判断，现有测试一条都不会红（实测过，355 全绿）。
    //
    // 但哪天有人加了第二个 .adjustment 写入口、note 另有含义（这里造的是
    // 两笔备注都写「年度盘账」的调整），只按「note 相同」分组就会把
    // **一整批不相干的调整塌成一条**：
    // 用户扣掉的账凭空回来，方向是「多」，量级不封顶。
    //
    // 这条测试就是拦在那儿的。别因为「现在造不出这种数据」就删掉它——
    // 现在造不出，正是它存在的理由。
    //
    // ⚠️ 备注必须**非空**。写 `note: nil` 的话两个版本都走 `guard let note`
    // 那条路提前 continue，测试会为错误的原因通过——初版就是这么写的，
    // 变异跑出 356 全绿才发现。
    let (ledger, ctx, item) = try makeLedger()
    let now = 北京(7, 28, 9, 0)
    _ = try ledger.record(item: item, amount: 1000, source: .counter,
                          startedAt: now, endedAt: now, at: now, timeZone: 北京时间)
    for _ in 0..<2 {
        ctx.insert(PracticeSession(
            item: item, dayKey: 20260728, tzOffsetMinutes: 480,
            amount: -100, startedAt: now, endedAt: now, source: .adjustment,
            deviceName: "iPhone·TEST", note: "年度盘账", createdAt: now
        ))
    }
    try ctx.save()

    #expect(try ledger.rawTotal(on: 20260728, itemID: item.id) == 800,
            "两笔各不相干的调整不是同一组，1000 − 100 − 100 = 800")
    #expect(try ledger.sessions(on: 20260728, itemID: item.id).count == 3,
            "一笔原记录 + 两笔调整，一条都不该被吞")
}
