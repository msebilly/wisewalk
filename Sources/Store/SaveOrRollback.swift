import Foundation
import SwiftData

extension ModelContext {
    /// 落盘，失败就把 context 里的残留撤干净再把错抛出去。
    ///
    /// ⛔ **本 App 里除了这一句，任何地方都不许直接调 `save()`**
    /// （`落盘只许走saveOrRollback` 扫源码钉着这条）。
    ///
    /// ## 为什么
    ///
    /// 实测（SDK 26.5）：`save()` 抛错时 store 会一致地回滚，但 **context 的 pending
    /// 改动不会被清掉**。而账本、定课、草稿**三个 store 共用同一个 mainContext**——
    /// 一处失败，那半截意图就一直挂在 context 里，被下一次**无关的** save 顺手提交。
    ///
    /// 两条实际够得着的路：
    ///
    ///     补记 500 声 → 磁盘满，save 抛错 → 界面老老实实说「记录失败」→
    ///     用户转身去点计数器 → DraftStore.update 每点一下就 save 一次 →
    ///     那笔 500 声悄没声儿地落了盘。**告诉用户没记上、账本上却有。**
    ///
    ///     commit 失败 → 界面提示「记录失败」→ 用户点「放弃」→
    ///     discard 里那次 save 把残留的流水一并落盘 →
    ///     **用户明明放弃了却记上了一笔。**
    ///
    /// 两条都顶着「一声都不能多」。
    ///
    /// ## 回滚的范围说清楚
    ///
    /// `rollback()` 撤的是**整个 context** 的待提交改动，不只是这一次的。
    /// 这在本 App 里是安全的，因为除了 `DayLedger.stage()`（它唯一的调用方
    /// `DraftStore.commit` 紧接着就落盘）之外，没有任何地方会**故意**把改动
    /// 挂在 context 里过夜。真要加这样的地方，先回来读这一段。
    func saveOrRollback() throws {
        do {
            try save()
        } catch {
            rollback()
            throw error
        }
    }
}
