import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@MainActor
private func makeDraftStore() throws -> (DraftStore, DayLedger, ModelContext, PracticeItem) {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let item = PracticeItem(name: "念佛", measureType: .count, unit: "声", dailyGoal: 1000)
    ctx.insert(item)
    try ctx.save()
    let ledger = DayLedger(context: ctx, deviceName: "iPhone·TEST")
    return (DraftStore(context: ctx, ledger: ledger), ledger, ctx, item)
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
@Test func 开草稿并累加() throws {
    let (drafts, _, _, item) = try makeDraftStore()
    let d = try drafts.begin(itemID: item.id, source: .counter, at: 北京(7, 28, 9, 0))
    #expect(d.amount == 0)
    try drafts.update(d, amount: 108, at: 北京(7, 28, 9, 5))
    #expect(try drafts.draft(for: item.id)?.amount == 108)
}

@MainActor
@Test func 同一定课重复begin沿用旧草稿而不是新开一份() throws {
    // 否则用户退出计数器再进来就会凭空多出一份草稿，恢复时不知道该信哪个。
    let (drafts, _, _, item) = try makeDraftStore()
    let first = try drafts.begin(itemID: item.id, source: .counter, at: 北京(7, 28, 9, 0))
    try drafts.update(first, amount: 50, at: 北京(7, 28, 9, 1))
    let second = try drafts.begin(itemID: item.id, source: .counter, at: 北京(7, 28, 9, 2))
    #expect(second.sessionID == first.sessionID, "应当沿用旧草稿")
    #expect(second.amount == 50, "已经念的 50 声不能被清零")
    #expect(try drafts.pendingDrafts().count == 1)
}

@MainActor
@Test func 不同定课各有各的草稿() throws {
    let (drafts, _, ctx, item) = try makeDraftStore()
    let other = PracticeItem(name: "打坐", measureType: .duration)
    ctx.insert(other)
    try ctx.save()
    try drafts.begin(itemID: item.id, source: .counter, at: 北京(7, 28, 9, 0))
    try drafts.begin(itemID: other.id, source: .timer, at: 北京(7, 28, 9, 1))
    #expect(try drafts.pendingDrafts().count == 2)
    #expect(try drafts.draft(for: other.id)?.source == .timer)
}

@MainActor
@Test func 提交后草稿消失流水出现且只有一次save() throws {
    let (drafts, ledger, ctx, item) = try makeDraftStore()
    let start = 北京(7, 28, 9, 0)
    let end = 北京(7, 28, 9, 30)
    let d = try drafts.begin(itemID: item.id, source: .counter, at: start)
    try drafts.update(d, amount: 108, at: end)

    let s = try drafts.commit(d, item: item, amount: 108, at: end, timeZone: 北京时间)

    #expect(s.amount == 108)
    #expect(s.startedAt == start, "起始时刻应取自草稿，而不是提交的那一刻")
    #expect(s.endedAt == end)
    #expect(try drafts.pendingDrafts().isEmpty, "草稿没清掉")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108)
    #expect(!ctx.hasChanges, "commit 之后不该留下未落盘的改动")
}

@MainActor
@Test func 提交用的是草稿预生成的编号() throws {
    let (drafts, ledger, _, item) = try makeDraftStore()
    let now = 北京(7, 28, 9, 0)
    let d = try drafts.begin(itemID: item.id, source: .counter, at: now)
    let expectedID = d.sessionID
    let s = try drafts.commit(d, item: item, amount: 30, at: now, timeZone: 北京时间)
    #expect(s.id == expectedID)
    #expect(try ledger.exists(sessionID: expectedID))
}

@MainActor
@Test func 丢弃草稿不产生任何流水() throws {
    let (drafts, ledger, _, item) = try makeDraftStore()
    let now = 北京(7, 28, 9, 0)
    let d = try drafts.begin(itemID: item.id, source: .counter, at: now)
    try drafts.update(d, amount: 99, at: now)
    try drafts.discard(d)
    #expect(try drafts.pendingDrafts().isEmpty)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 0, "丢弃不该留下账")
}

@MainActor
@Test func 对账会清掉流水其实已入账的草稿() throws {
    // §4.5 第 3 条。模拟「流水落盘了但草稿没删掉」这种跨 store 半途死亡。
    let (drafts, ledger, ctx, item) = try makeDraftStore()
    let now = 北京(7, 28, 9, 0)
    let d = try drafts.begin(itemID: item.id, source: .counter, at: now)
    try drafts.update(d, amount: 108, at: now)
    // 绕过 commit，只写流水不删草稿
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间, id: d.sessionID)
    #expect(try drafts.pendingDrafts().count == 1, "前提：草稿还在")

    let live = try drafts.reconcilePendingDrafts()

    #expect(live.isEmpty, "这笔已经入账了，不该再来打扰用户")
    #expect(try drafts.pendingDrafts().isEmpty, "对账应当把它删掉")
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 108, "已入账的流水一分不能少")
    #expect(!ctx.hasChanges)
}

@MainActor
@Test func 对账保留真正未入账的草稿() throws {
    let (drafts, _, _, item) = try makeDraftStore()
    let now = 北京(7, 28, 9, 0)
    let d = try drafts.begin(itemID: item.id, source: .counter, at: now)
    try drafts.update(d, amount: 108, at: now)
    let live = try drafts.reconcilePendingDrafts()
    #expect(live.count == 1)
    #expect(live.first?.amount == 108)
}

@MainActor
@Test func 对账混合场景只清已入账的那份() throws {
    let (drafts, ledger, ctx, item) = try makeDraftStore()
    let other = PracticeItem(name: "打坐", measureType: .duration)
    ctx.insert(other)
    try ctx.save()
    let now = 北京(7, 28, 9, 0)

    let done = try drafts.begin(itemID: item.id, source: .counter, at: now)
    try drafts.update(done, amount: 108, at: now)
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间, id: done.sessionID)

    let live = try drafts.begin(itemID: other.id, source: .timer, at: now)
    try drafts.touch(live, at: 北京(7, 28, 9, 20))

    let remaining = try drafts.reconcilePendingDrafts()
    #expect(remaining.count == 1)
    #expect(remaining.first?.itemID == other.id)
}

@MainActor
@Test func 心跳只动时刻不动量() throws {
    let (drafts, _, _, item) = try makeDraftStore()
    let start = 北京(7, 28, 9, 0)
    let d = try drafts.begin(itemID: item.id, source: .timer, at: start)
    try drafts.update(d, amount: 5, at: start)
    try drafts.touch(d, at: 北京(7, 28, 9, 20))
    #expect(d.amount == 5, "心跳不该改动量")
    #expect(d.updatedAt == 北京(7, 28, 9, 20))
    #expect(d.startedAt == start, "心跳更不该改动起始时刻")
}

@MainActor
@Test func 待恢复草稿按开始时间排序() throws {
    let (drafts, _, ctx, item) = try makeDraftStore()
    let b = PracticeItem(name: "打坐")
    let c = PracticeItem(name: "拜佛")
    ctx.insert(b); ctx.insert(c)
    try ctx.save()
    try drafts.begin(itemID: c.id, source: .counter, at: 北京(7, 28, 11, 0))
    try drafts.begin(itemID: item.id, source: .counter, at: 北京(7, 28, 9, 0))
    try drafts.begin(itemID: b.id, source: .timer, at: 北京(7, 28, 10, 0))
    #expect(try drafts.pendingDrafts().map(\.itemID) == [item.id, b.id, c.id])
}

@MainActor
@Test func 提交失败后不留残念给下一次save() throws {
    // 这条不测 DraftStore 的正常路径，它钉的是 `commit` 里那句 `context.rollback()`
    // 的**存在理由**：实测（SDK 26.5）SwiftData 在 save 抛错后会一致地回滚 store，
    // 但**不会**清空 context 的 pending 改动。若哪天这个语义变了（残留自动消失），
    // 本条的前半段会变红，届时 commit 里的 rollback 就可以删掉。
    let (_, ledger, ctx, item) = try makeDraftStore()
    let now = 北京(7, 28, 9, 0)

    // 模拟「commit 半途而废」：流水已 stage，但那次 save 没成
    try ledger.stage(item: item, amount: 108, source: .counter,
                     startedAt: now, at: now, timeZone: 北京时间)
    #expect(ctx.hasChanges)

    // 一次完全无关的落盘，把残留那笔顺手带了出去——这就是要防的事
    try ctx.save()
    #expect(try ModelContext(ctx.container).fetch(FetchDescriptor<PracticeSession>()).count == 1,
            "残留的 stage 会被下一次无关的 save 提交，所以 commit 失败时必须 rollback")

    // rollback 之后，同样的残留就带不出去了
    try ledger.stage(item: item, amount: 999, source: .counter,
                     startedAt: now, at: now, timeZone: 北京时间)
    ctx.rollback()
    try ctx.save()
    #expect(try ModelContext(ctx.container).fetch(FetchDescriptor<PracticeSession>()).count == 1,
            "rollback 之后那笔 999 不该再出现")
}
