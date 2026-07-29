import Foundation
import SwiftData

/// 账本的**唯一**写入口。
///
/// 「只增不改不删」这条纪律如果散落在各个界面里就守不住，
/// 所以所有写操作收口到这里。界面层不许直接 `context.insert(PracticeSession…)`。
///
/// 标注 `@MainActor` 是因为 `ModelContext` 不是 Sendable，必须固定在一个执行域上。
/// v1 的写入量（一天几十笔）远达不到需要后台上下文的程度。
@MainActor
final class DayLedger {
    private let context: ModelContext
    private let deviceName: String

    init(context: ModelContext, deviceName: String) {
        self.context = context
        self.deviceName = deviceName
    }

    // MARK: - 写

    /// 记一笔。
    ///
    /// - Parameter id: 预生成编号。崩溃恢复时传入草稿里的编号，
    ///   本方法会先查重，已入账则直接返回既有记录，不会重复计数。
    @discardableResult
    func record(
        item: PracticeItem,
        amount: Int,
        source: SessionSource,
        startedAt: Date,
        endedAt: Date? = nil,
        at now: Date = Date(),
        dayStartHour: Int = 0,
        timeZone: TimeZone = .current,
        id: UUID = UUID(),
        note: String? = nil
    ) throws -> PracticeSession {
        if let existing = try fetch(sessionID: id) {
            return existing
        }

        let offset = DayKey.currentOffsetMinutes(at: now, timeZone: timeZone)
        let session = PracticeSession(
            id: id,
            item: item,
            dayKey: DayKey.make(from: now, tzOffsetMinutes: offset, dayStartHour: dayStartHour),
            tzOffsetMinutes: offset,
            amount: amount,
            startedAt: startedAt,
            endedAt: endedAt,
            source: source,
            deviceName: deviceName,
            note: note,
            createdAt: now
        )
        context.insert(session)
        try context.save()
        return session
    }

    /// 撤销一笔：追加一笔等额负数的 `.adjustment`。**原记录纹丝不动。**
    ///
    /// 新记录落在**原记录的 dayKey** 上而不是今天——
    /// 撤销昨天的误记，不该让今天的账面莫名少一截。
    @discardableResult
    func revoke(
        _ session: PracticeSession,
        at now: Date = Date(),
        timeZone: TimeZone = .current
    ) throws -> PracticeSession {
        let adjustment = PracticeSession(
            item: session.item,
            dayKey: session.dayKey,
            tzOffsetMinutes: session.tzOffsetMinutes,
            amount: -session.amount,
            startedAt: now,
            endedAt: now,
            source: .adjustment,
            deviceName: deviceName,
            note: "revoke:\(session.id.uuidString)",
            createdAt: now
        )
        context.insert(adjustment)
        try context.save()
        return adjustment
    }

    // MARK: - 读

    /// 某天某项的全部流水。
    ///
    /// 先按 dayKey 取库、再在内存里按定课项过滤，是刻意为之：
    /// `#Predicate` 穿透可选关系（`$0.item?.id == x`）在 SwiftData 上行为不稳，
    /// 而一天的流水至多几十条，内存过滤的代价可以忽略。
    func sessions(on dayKey: Int, itemID: UUID) throws -> [PracticeSession] {
        let key = dayKey
        let sameDay = try context.fetch(
            FetchDescriptor<PracticeSession>(predicate: #Predicate { $0.dayKey == key })
        )
        return sameDay.filter { $0.item?.id == itemID }
    }

    /// 某天某项的显示总数（负数已 clamp 到 0）。
    func total(on dayKey: Int, itemID: UUID) throws -> Int {
        LedgerMath.displayTotal(try sessions(on: dayKey, itemID: itemID))
    }

    /// 某天某项的账本原值（可能为负）。诊断与导出使用。
    func rawTotal(on dayKey: Int, itemID: UUID) throws -> Int {
        LedgerMath.rawTotal(try sessions(on: dayKey, itemID: itemID))
    }

    /// 该编号是否已入账。崩溃恢复前必查。
    func exists(sessionID: UUID) throws -> Bool {
        try fetch(sessionID: sessionID) != nil
    }

    private func fetch(sessionID: UUID) throws -> PracticeSession? {
        let target = sessionID
        var descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate { $0.id == target }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
