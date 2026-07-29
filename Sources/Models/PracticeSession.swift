import Foundation
import SwiftData

/// 一笔修行流水。**只增不改不删。**
///
/// 撤销的做法是追加一笔等额负数的 `.adjustment`，绝不删除原记录。
/// 理由见 design-spec §4.2：CloudKit 的冲突解决是**整记录级** LWW，
/// 一旦把「今日总数」这类可变字段存进去，iPhone 记的 800 声
/// 会被 iPad 上那条较晚写入的 500 声整条盖掉，凭空少 300 声。
/// 改成流水后每笔都是独立记录，两台设备各写各的，合并即求和——
/// 本质上是 CRDT 里的 PN-Counter。
///
/// 写入粒度是**一次修行结束记一笔**，不是每念一句记一笔。
/// 重度用户五年也只有几万条。
@Model
final class PracticeSession {
    var id: UUID = UUID()

    /// 所属定课项。CloudKit 要求关系必须可选。
    /// 为 nil 表示定课项已被清理，但这笔流水依然作数。
    var item: PracticeItem?

    /// yyyyMMdd。**写入后永不重算。**
    var dayKey: Int = 0

    /// 写入当时的本地时区偏移（分钟）。东八区 480。
    /// 有了它才能在任何设备上还原「这笔是哪天记的」。
    var tzOffsetMinutes: Int = 0

    /// 计数类为遍数，计时类为**秒**，打勾类恒为 1。
    /// `.adjustment` 可为负。**不设上限**——闭关的师兄一天几万声很正常。
    var amount: Int = 0

    var startedAt: Date = Date.distantPast
    var endedAt: Date?

    /// `SessionSource` 的原始值。SwiftData + CloudKit 要求枚举以字符串落库。
    var sourceRaw: String = SessionSource.manual.rawValue

    var deviceName: String = ""
    var note: String?
    var createdAt: Date = Date.distantPast

    init(
        id: UUID = UUID(),
        item: PracticeItem? = nil,
        dayKey: Int,
        tzOffsetMinutes: Int,
        amount: Int,
        startedAt: Date,
        endedAt: Date? = nil,
        source: SessionSource,
        deviceName: String,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.item = item
        self.dayKey = dayKey
        self.tzOffsetMinutes = tzOffsetMinutes
        self.amount = amount
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.sourceRaw = source.rawValue
        self.deviceName = deviceName
        self.note = note
        self.createdAt = createdAt
    }

    /// 计算属性不会被 SwiftData 持久化，仅作类型安全的读写门面。
    var source: SessionSource {
        get { SessionSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }
}
