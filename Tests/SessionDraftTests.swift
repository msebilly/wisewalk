import Testing
import SwiftData
import Foundation
@testable import WiseWalk

@Test func 草稿绝不在同步schema里() {
    // 这是本卷最重要的一条守卫。
    // 草稿若同步出去：A 手机念到一半崩了，B 手机开机就弹「要恢复这笔吗」，
    // 用户点确认 → 同一笔功课记两遍。正是 §4.5 要根除的重复写入。
    let synced = Set(ModelContainerFactory.syncedSchema.entities.map(\.name))
    let local = Set(ModelContainerFactory.localSchema.entities.map(\.name))
    #expect(!synced.contains("SessionDraft"),
            "草稿混进了同步 schema。它会被同步到别的设备，造成同一笔功课重复记账")
    #expect(local == ["SessionDraft"], "本地库应当且仅当装着草稿，实际是 \(local)")
    #expect(synced == ["PracticeItem", "PracticeSession", "DaySnapshot"])
    #expect(synced.isDisjoint(with: local), "两套 schema 不许有交集")
}

@MainActor
@Test func 两套configuration能共存且各自可读写() throws {
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let item = PracticeItem(name: "念佛")
    ctx.insert(item)
    ctx.insert(SessionDraft(itemID: item.id, amount: 3,
                            startedAt: Date(), updatedAt: Date(), source: .counter))
    try ctx.save()
    #expect(try ctx.fetch(FetchDescriptor<SessionDraft>()).count == 1, "本地库写不进去")
    #expect(try ctx.fetch(FetchDescriptor<PracticeItem>()).count == 1, "同步库写不进去")
}

@MainActor
@Test func 一次save可同时写流水与删草稿() throws {
    // §4.5 第 1 条：写入 Session 与清除草稿必须同一事务。
    // 两个 store 分属两个文件，能做到同一次 save 是本卷架构成立的前提。
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let item = PracticeItem(name: "念佛")
    ctx.insert(item)
    let draft = SessionDraft(itemID: item.id, amount: 108,
                             startedAt: Date(), updatedAt: Date(), source: .counter)
    ctx.insert(draft)
    try ctx.save()

    let session = PracticeSession(id: draft.sessionID, item: item, dayKey: 20260728,
                                  tzOffsetMinutes: 480, amount: 108, startedAt: Date(),
                                  source: .counter, deviceName: "T")
    ctx.insert(session)
    ctx.delete(draft)
    try ctx.save()

    #expect(try ctx.fetch(FetchDescriptor<SessionDraft>()).isEmpty, "同一次 save 应已删掉草稿")
    #expect(try ctx.fetch(FetchDescriptor<PracticeSession>()).count == 1, "同一次 save 应已写入流水")
}

@Test func 草稿默认来源是计数器且能改成计时器() {
    let d = SessionDraft(itemID: UUID(), startedAt: .distantPast,
                         updatedAt: .distantPast, source: .timer)
    #expect(d.source == .timer)
    d.source = .counter
    #expect(d.sourceRaw == "counter")
}

@Test func 草稿来源无法识别时退化为计数器() {
    // 与 ScheduleRule 同一条原则：宁可退化成一个安全的默认，
    // 也不能让崩溃恢复因为解析失败而丢掉用户已经念了的数。
    let d = SessionDraft(itemID: UUID(), startedAt: .distantPast,
                         updatedAt: .distantPast, source: .counter)
    d.sourceRaw = "从未来的版本同步回来的新来源"
    #expect(d.source == .counter)
}

@MainActor
@Test func 草稿携带预生成的流水编号() throws {
    // §4.5 第 2 条。提交时拿它调 record(id:)，重放也只会记一笔。
    let ctx = ModelContext(try ModelContainerFactory.inMemory())
    let item = PracticeItem(name: "念佛")
    ctx.insert(item)
    let d = SessionDraft(itemID: item.id, startedAt: Date(), updatedAt: Date(), source: .counter)
    ctx.insert(d)
    try ctx.save()

    let ledger = DayLedger(context: ctx, deviceName: "T")
    let now = Date()
    let s1 = try ledger.record(item: item, amount: 5, source: .counter, startedAt: now, at: now, id: d.sessionID)
    let s2 = try ledger.record(item: item, amount: 5, source: .counter, startedAt: now, at: now, id: d.sessionID)
    #expect(s1.id == s2.id, "同一编号重放必须命中查重")
    #expect(try ctx.fetch(FetchDescriptor<PracticeSession>()).count == 1, "重放记出了第二笔")
}
