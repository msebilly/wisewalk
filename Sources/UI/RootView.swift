import SwiftUI

/// 根视图。持有导航栈，并在放行之前先把 §4.5 的草稿清算走完。
struct RootView: View {
    let env: AppEnvironment

    @Environment(\.theme) private var theme
    @State private var path = NavigationPath()
    @State private var recovery: RecoveryCoordinator
    @State private var today: TodayViewModel
    @State private var failure: String?
    /// 恢复弹窗的开关**必须是可写的 `@State`，不能是 `.constant(!pending.isEmpty)`**。
    ///
    /// SwiftUI 关掉 alert 时会把 `false` 写回这个 binding。只读 binding 把这次写入
    /// 丢掉，binding 于是永远说「还开着」而 alert 已经拆了——遮罩留在屏上、
    /// `.disabled(!isReady)` 永不解除，**整个今日页再也点不动**。
    /// 触发它只需要点一下 SwiftUI 自动补的那个 `Cancel`（见 `postpone()`）。
    ///
    /// 换成 `@State` 之后，「谁来开、谁来关」由 `syncRecoveryPrompt()` 一处说了算，
    /// 它读的还是 `pending` —— 于是 `accept()` 抛错、pending 故意留着的那条路
    /// （`查不到功课时记上要报错而不是悄悄什么都不做`）也能把弹窗**重新**支起来。
    @State private var showRecovery = false

    init(env: AppEnvironment) {
        self.env = env
        _recovery = State(initialValue: RecoveryCoordinator(env: env))
        _today = State(initialValue: TodayViewModel(ledger: env.ledger, items: env.items))
    }

    /// 清算跑完、且待裁决的草稿都处理干净了，才放用户进去。
    /// 顺序依赖：没跑完就让用户进计时器，`TimerViewModel.start()`
    /// 会承接那份三天前的草稿接着计时。
    static func isReady(_ rc: RecoveryCoordinator) -> Bool {
        rc.didRun && rc.pending.isEmpty
    }

    /// **必须说出这笔算在哪天。**
    ///
    /// `accept` 把它记在功课发生的那天（`at: draft.updatedAt`），这是对的——
    /// 可代价是：隔夜才重开 App 的用户按完「记上」，回到今日页会发现**什么都没变**。
    /// 他刚认下的 108 声像是凭空消失了，于是照着记忆再补记一遍，就成了 216。
    /// 「一声都不能多」在这里不是被一行代码破掉的，是被一句没说出口的话破掉的。
    ///
    /// 措辞只陈述事实、不判断是不是今天——同一天崩溃再重开也是常事，
    /// 那时说「不算今天」就是撒谎。写出日期，用户自己认得出。
    ///
    /// `timeZone` 留作参数是为了测试能注入固定时区：本机是 PDT，
    /// 拿 `.current` 去断言就是拿实现那把尺子量实现（纪律 ⑬）。
    /// - Parameter alreadyOnBooksText: 这一笔要落的那天、那门功课账上**另外**已经有的数。
    ///   `nil` 就一个字也不提——那天真没有，或者算不出来。
    ///   见 `RecoveryCoordinator.alreadyOnBooks`：只摆事实，不出主意。
    static func recoveryMessage(_ item: PendingRecovery,
                                timeZone: TimeZone = .current,
                                alreadyOnBooksText: String? = nil) -> String {
        let kind = item.source == .timer ? "计时" : "计数"
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = timeZone
        f.dateFormat = "M月d日 HH:mm"
        var lines = "上次「\(item.itemName)」\(kind)到 \(item.amountText) 时应用退出了，还没记上。\n"
            + "记上会算在 \(f.string(from: item.endedAt))，也就是当时那一天。"
        // 「另外」这两个字不能省：少了它，他会以为这个数里已经含着眼下这一笔，
        // 于是点「不记了」——而那一笔其实还没记上。
        if let already = alreadyOnBooksText {
            lines += "\n那一天「\(item.itemName)」另外已经记了 \(already)。"
        }
        return lines
    }

    var body: some View {
        NavigationStack(path: $path) {
            TodayView(vm: today, settings: env.settings, path: $path)
                // 清算没走完就不放行。`.disabled` 只加在这里，
                // 弹窗挂在外层的 NavigationStack 上——加在被禁用的子树里，
                // 连「记上」按钮都会点不动。
                .disabled(!Self.isReady(recovery))
                // 「记录只在这台设备上」这件事非说不可，但只在真出事时说。
                // 挂 `safeAreaInset` 而不是塞进 `TodayView`：这不是今日的账，
                // 是整个库的状态，不该混进那一页的列表语义里。
                .safeAreaInset(edge: .bottom) { syncNotice }
                // 底色挂在栈**内部**每一页上，不能只挂在栈外的 `.themed()` 里——
                // `NavigationStack` 自己那层不透明系统底会把它整个盖住。详见 `PageBackground`。
                .pageBackground()
                .navigationDestination(for: Route.self) { destination($0).pageBackground() }
        }
        .themed()
        .task { runRecovery() }
        // 待裁决的草稿逐个问。一次问一份，问得清楚，也免得用户为了关掉弹窗胡乱点。
        // 三个按钮一个都不能少：**只写两个的话 SwiftUI 会自己补第三个**，
        // 标题是系统英文 `Cancel`、action 是空的，点下去就把界面锁死（见 `postpone()`）。
        .alert("有一笔没记上", isPresented: $showRecovery) {
            Button("记上") { accept() }
            Button("不记了", role: .destructive) { discard() }
            Button("以后再说", role: .cancel) { recovery.postpone() }
        } message: {
            Text(recovery.pending.first.map {
                Self.recoveryMessage($0, alreadyOnBooksText: recovery.alreadyOnBooksText)
            } ?? "")
        }
        .alert("出了点问题", isPresented: .presenting($failure)) {
            // 先把话说完，再把没裁决完的那些重新支起来——两个 alert 不抢同一块屏。
            Button("知道了") { failure = nil; syncRecoveryPrompt() }
        } message: { Text(failure ?? "") }
    }

    /// 「记录只在这台设备上」——**闷声降级是本产品最怕的形状**，所以非说不可。
    /// 但只在真出事时说：路通着就一个字都不说（`LedgerSyncStatus.notice` 返回 nil）。
    ///
    /// ⚠️ 用 `secondaryText` 而不是红色警示：这不是用户做错了什么，
    /// 也不是他此刻能修好的事。吓唬他没有用，把事实摆出来就够了。
    @ViewBuilder
    private var syncNotice: some View {
        if let text = env.syncStatus.notice {
            Text(text)
                .font(.footnote)
                .foregroundStyle(theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(.thinMaterial)
        }
    }

    @ViewBuilder
    private func destination(_ route: Route) -> some View {
        switch route {
        case .counter(let id):
            if let item = try? env.items.item(id: id) {
                CounterView(vm: CounterViewModel(item: item, drafts: env.drafts, ledger: env.ledger),
                            settings: env.settings,
                            onFinish: { reloadToday() })
            }
        case .timer(let id):
            if let item = try? env.items.item(id: id) {
                TimerView(vm: TimerViewModel(item: item, drafts: env.drafts, ledger: env.ledger),
                          settings: env.settings,
                          onFinish: { reloadToday() })
            }
        case .manualEntry:
            ManualEntryView(vm: ManualEntryViewModel(ledger: env.ledger, items: env.items),
                            settings: env.settings)
                .onDisappear { reloadToday() }
        case .itemList:
            ItemListView(store: env.items, path: $path)
                .onDisappear { reloadToday() }
        case .itemEditor(let id):
            // ⛔ `id != nil` 却取不到项时，**绝不能**把 `editing` 传成 nil。
            // `ItemEditorViewModel.save()` 见 `editing == nil` 就走 `store.create`——
            // 用户点的是「编辑念佛」，按下保存却新建出**第二个念佛**。
            // 从此今日页两门念佛，圆满的分母凭空翻倍，**那天再不可能圆满**，
            // 而他完全看不出是为什么（与 Task 13「装配阶段又装一套内置定课」同罪）。
            //
            // `try?` 把 fetch 的抛错也吞成 nil，所以这条路不只在「项不存在」时才通。
            // 本卷 `PracticeItem` 只归档不硬删、无同步，够得着的机会很小；
            // 第 3 卷接 CloudKit 之后另一台设备的删除会让它变得寻常。
            // 与 `.counter` / `.timer` 一样，取不到就什么都不渲染——空白页不好看，
            // 但它不会往账本里写东西。
            if let editing = id {
                if let item = try? env.items.item(id: editing) {
                    ItemEditorView(vm: ItemEditorViewModel(store: env.items, editing: item))
                }
            } else {
                ItemEditorView(vm: ItemEditorViewModel(store: env.items, editing: nil))
            }
        }
    }

    private func runRecovery() {
        do {
            try recovery.runAtLaunch()
            try today.reload(dayStartHour: env.settings.dayStartHour)
            syncRecoveryPrompt()
        } catch { failure = error.localizedDescription }
    }

    /// 弹窗开关只在这一处拨。读的是 `pending`，所以三种收场各归各位：
    /// 还剩一份就接着问（两份草稿一份一份来）、问完了就放行、
    /// `accept()` 抛错留着的那份会被**重新**支起来。
    ///
    /// ⛔ **必须先落回 `false` 再支起来，中间隔一个 runloop。**
    /// SwiftUI 是在按钮 action 跑完之后才把 alert 收掉的。若此刻把
    /// `showRecovery` 从 `true` 又写成 `true`，那**不算一次状态变化**——
    /// 弹窗不会重新呈现，而 `.disabled(!isReady)` 还锁着（`pending` 非空），
    /// 于是屏上遮罩不散、哪儿都点不动，跟从前那个只读 binding 死得一模一样。
    /// 手点两份草稿实测过：答完第一份，第二份不弹，界面当场锁死。
    private func syncRecoveryPrompt() {
        showRecovery = false
        guard !recovery.pending.isEmpty else { return }
        Task { @MainActor in
            // 等的是 UIKit 那套 alert 的关闭动画。`Task` 单靠调度让不出这段时间，
            // 实测第二份照样弹不出来、界面照样锁死，必须真的隔开。
            // 停顿本身也不坏：两份草稿之间空一下，用户才看得出这是**两笔**，
            // 而不是一笔弹窗闪了两下。
            try? await Task.sleep(for: .milliseconds(450))
            showRecovery = true
        }
    }

    private func accept() {
        guard let first = recovery.pending.first else { return }
        do {
            try recovery.accept(first)
            try today.reload(dayStartHour: env.settings.dayStartHour)
            syncRecoveryPrompt()
        } catch {
            // 出错先说话；恢复弹窗等用户点完「知道了」再重新支起来。
            failure = error.localizedDescription
        }
    }

    private func discard() {
        guard let first = recovery.pending.first else { return }
        do {
            try recovery.discard(first)
            try today.reload(dayStartHour: env.settings.dayStartHour)
            syncRecoveryPrompt()
        } catch { failure = error.localizedDescription }
    }

    private func reloadToday() {
        do { try today.reload(dayStartHour: env.settings.dayStartHour) }
        catch { failure = error.localizedDescription }
    }
}
