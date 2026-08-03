import Testing
import Foundation

/// 落盘的规矩只有一条：**失败就把 context 里的残留撤干净**。
///
/// 这条规矩本来写在两处注释里（`DayLedger.saveOrRollback` 和 `DraftStore.commit`），
/// 而代码里还有九处裸 `context.save()` 没照做——注释拦不住人，只有测试拦得住。
@Suite struct 落盘规矩 {

    /// 全 App 只许有一处直接调 `context.save()`，就是 `saveOrRollback()` 自己。
    ///
    /// ## 为什么这条值得用扫源码的方式来钉
    ///
    /// 实测（SDK 26.5）：`save()` 抛错时 store 会一致地回滚，但 **context 的 pending
    /// 改动不会被清掉**。而**三个 store 共用同一个 mainContext**——
    /// 一处失败，残留就挂在那儿，被下一次**无关的** save 顺手提交。
    ///
    /// `DraftStore.commit` 的注释里已经把最坏那条路写出来了：
    ///
    ///     commit 失败 → 界面提示「记录失败」→ 用户点「放弃」→
    ///     discard 里那次 save 把残留的流水一并落盘 → 用户明明放弃了却记上了一笔
    ///
    /// **而 `discard` 自己当时就是一句裸 save。** 写着这段注释的人，
    /// 没有回头看紧挨着的下一个函数。
    ///
    /// 这类「同一个判断散在多处、漏掉几处」的病，本仓库已经犯过两次
    ///（`6c12439` 3600 倍丢账、`598f7b6` 无障碍标签），所以这次不靠自觉。
    @Test func 落盘只许走saveOrRollback() throws {
        let sources = URL(filePath: #filePath)
            .deletingLastPathComponent()   // Tests/
            .deletingLastPathComponent()   // 仓库根
            .appending(path: "Sources")
        // 找不到源码就红。**不许悄悄跳过**——一条永远绿的守门测试等于没有。
        #expect(FileManager.default.fileExists(atPath: sources.path),
                "找不到 Sources/，这条测试什么也没守住：\(sources.path)")

        var offenders: [String] = []
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        for case let url as URL in files where url.pathExtension == "swift" {
            let name = url.lastPathComponent
            // 助手自己那一句是唯一的例外，它就是这条规矩的实现。
            if name == "SaveOrRollback.swift" { continue }
            for (i, raw) in (try String(contentsOf: url, encoding: .utf8))
                .components(separatedBy: .newlines).enumerated() {
                // 注释里提这个名字是允许的（好几处文档正在解释这条规矩）。
                let code = raw.components(separatedBy: "//").first ?? raw
                if code.contains("context.save()") {
                    offenders.append("\(name):\(i + 1)")
                }
            }
        }
        #expect(offenders.isEmpty, """
            这些地方直接调了 context.save()，失败时不会清残留，\
            会被下一次无关的 save 顺手提交：\(offenders.joined(separator: ", "))
            """)
    }
}
