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

/// 数 `ModelContext.didSave` 的次数。通知块是 `@Sendable` 的，捕获不了外层的 `var`，
/// 所以要个能跨隔离域安全累加的小盒子。
private final class SaveCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func bump() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
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

@MainActor
@Test func 量法变了就不沿用旧草稿() throws {
    // 定课的量法是可以改的（PracticeItemStore.update 开放 measureType）。
    // 改完之后旧草稿的 amount 与 startedAt 在新量法下每个字段都是错的：
    // 一份 .timer 草稿被计数器沿用，恢复时会按 updatedAt - startedAt 折成几千秒，
    // 弹窗写「念了几千声」，用户一确认就写进只增不减的账本。
    let (drafts, _, _, item) = try makeDraftStore()
    let old = try drafts.begin(itemID: item.id, source: .timer, at: 北京(7, 28, 9, 0))
    let oldID = old.sessionID
    try drafts.touch(old, at: 北京(7, 28, 10, 0))

    let fresh = try drafts.begin(itemID: item.id, source: .counter, at: 北京(7, 28, 11, 0))
    #expect(fresh.sessionID != oldID, "应当另开一份，而不是把旧的那份改个 source")
    #expect(fresh.source == .counter)
    #expect(fresh.amount == 0)
    #expect(fresh.startedAt == 北京(7, 28, 11, 0), "startedAt 必须是这次开始的时刻")
    #expect(try drafts.pendingDrafts().count == 1, "旧草稿要删掉，不能两份并存")
}

@MainActor
@Test func 已入账的草稿不会被沿用否则接下来念的全白念() throws {
    // reconcilePendingDrafts 只在启动时跑。用户不重启 App、同一次会话里又进计数器，
    // 沿用一份已入账的草稿就等于接下来念的全部白念——commit 时 stage 按 sessionID
    // 查重会直接返回那笔旧流水，新念的一声也写不进去，而且不会有任何报错。
    let (drafts, ledger, _, item) = try makeDraftStore()
    let now = 北京(7, 28, 9, 0)
    let stranded = try drafts.begin(itemID: item.id, source: .counter, at: now)
    try drafts.update(stranded, amount: 108, at: now)
    // 模拟跨 store 半途死亡：流水落了，草稿没删
    try ledger.record(item: item, amount: 108, source: .counter,
                      startedAt: now, at: now, timeZone: 北京时间, id: stranded.sessionID)

    let fresh = try drafts.begin(itemID: item.id, source: .counter, at: 北京(7, 28, 10, 0))
    #expect(fresh.sessionID != stranded.sessionID)
    #expect(fresh.amount == 0)
    #expect(try drafts.pendingDrafts().count == 1)

    // 要害在这里：接着念的这 50 声必须真能记上
    try drafts.update(fresh, amount: 50, at: 北京(7, 28, 10, 1))
    try drafts.commit(fresh, item: item, amount: 50, at: 北京(7, 28, 10, 2), timeZone: 北京时间)
    #expect(try ledger.total(on: 20260728, itemID: item.id) == 158, "108 + 50，新念的一声都不能丢")
}

@MainActor
@Test func 提交只落盘一次() throws {
    // 这条钉的是「commit 用的是 ledger.stage 而不是 ledger.record」。
    // 两者签名兼容，换成 record 也能让其余测试全绿——但那样「写流水」与「删草稿」
    // 就落在两次 save 里，中间死掉会留下「流水已写、草稿还在」，
    // 下次启动恢复会问用户，用户一确认就记两遍。Task 4 拆出 stage 的全部理由在此。
    let (drafts, _, ctx, item) = try makeDraftStore()
    let now = 北京(7, 28, 9, 0)
    let d = try drafts.begin(itemID: item.id, source: .counter, at: now)
    try drafts.update(d, amount: 108, at: now)

    let saves = SaveCounter()
    // object 必须限定成本测试自己的 ctx：Swift Testing 默认并行跑，
    // 传 nil 会把别的测试的 save 也数进来。
    let token = NotificationCenter.default.addObserver(
        forName: ModelContext.didSave, object: ctx, queue: nil
    ) { _ in saves.bump() }
    defer { NotificationCenter.default.removeObserver(token) }

    try drafts.commit(d, item: item, amount: 108, at: now, timeZone: 北京时间)
    #expect(saves.count == 1, "写流水与删草稿必须落在同一次 save 里")
}
