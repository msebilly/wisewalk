import Foundation
import SwiftData

/// 一笔**尚未记进账本**的功课草稿。计数器 / 计时器进行中的状态就存在这里。
///
/// **绝不进 CloudKit。** 草稿是「这台设备此刻手上正在做的事」，不是数据。
/// 若它同步出去，A 手机念到一半崩了，B 手机开机就会弹出「要恢复这笔吗」，
/// 用户点了确认，同一笔功课记两遍——正是 §4.5 要根除的重复写入。
/// 故草稿放在独立的本地 configuration（`ModelContainerFactory.localSchema`），
/// 并有守卫测试盯着它别被挪进同步 schema。
///
/// **只存 itemID 不存关系**：跨 configuration 的关系不成立。
/// 这也符合草稿的性质——它是一张便条，不是账本记录。
///
/// 顺带一提：本实体不受 §4.6 那四条 CloudKit 约束管辖（它压根不同步），
/// 但仍照着写成「属性全有默认值」的样子，免得日后有人把它挪进同步 schema 时才发现不合规。
@Model
final class SessionDraft {
    /// **预生成**的流水编号（§4.5 第 2 条）。
    /// 提交时用它调 `DayLedger.record(id:)` / `stage(id:)`——
    /// 即便草稿没清干净，重放也只会命中查重分支，绝不会记第二笔。
    var sessionID: UUID = UUID()

    /// 所属定课项的编号。**刻意不是关系**：跨 store 的关系不成立。
    var itemID: UUID = UUID()

    /// 计数类为已点的遍数；计时类此处恒为 0，真正的量由 `startedAt…updatedAt` 推算。
    var amount: Int = 0

    var startedAt: Date = Date.distantPast

    /// 心跳时刻。计时器崩溃后无从得知 App 是何时死的，
    /// `updatedAt` 是能拿到的最好估计——恢复时据此推荐时长（见 `DraftRecovery`）。
    /// 若改用「现在 − startedAt」，App 崩在三天前就会给用户记上 72 小时的打坐。
    var updatedAt: Date = Date.distantPast

    /// `SessionSource` 的原始值，只会是 `.counter` 或 `.timer`。
    var sourceRaw: String = SessionSource.counter.rawValue

    init(
        sessionID: UUID = UUID(),
        itemID: UUID,
        amount: Int = 0,
        startedAt: Date,
        updatedAt: Date,
        source: SessionSource
    ) {
        self.sessionID = sessionID
        self.itemID = itemID
        self.amount = amount
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.sourceRaw = source.rawValue
    }

    /// 计算属性不落库，仅作类型安全的读写门面。
    /// 无法识别一律退化 `.counter`——与 `ScheduleRule` 同一条原则：
    /// 宁可退化成安全的默认，也不能让恢复流程因解析失败而丢掉用户已经念的数。
    var source: SessionSource {
        get { SessionSource(rawValue: sourceRaw) ?? .counter }
        set { sourceRaw = newValue.rawValue }
    }
}
