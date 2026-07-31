import SwiftUI

/// 根视图。持有导航栈，并在放行之前先把 §4.5 的草稿清算走完。
struct RootView: View {
    let env: AppEnvironment

    @State private var path = NavigationPath()
    @State private var recovery: RecoveryCoordinator
    @State private var today: TodayViewModel
    @State private var failure: String?

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

    static func recoveryMessage(_ item: PendingRecovery) -> String {
        let kind = item.source == .timer ? "计时" : "计数"
        return "上次「\(item.itemName)」\(kind)到 \(item.amountText) 时应用退出了，还没记上。要记上吗？"
    }

    var body: some View {
        NavigationStack(path: $path) {
            TodayView(vm: today, settings: env.settings, path: $path)
                // 清算没走完就不放行。`.disabled` 只加在这里，
                // 弹窗挂在外层的 NavigationStack 上——加在被禁用的子树里，
                // 连「记上」按钮都会点不动。
                .disabled(!Self.isReady(recovery))
                .navigationDestination(for: Route.self) { destination($0) }
        }
        .themed()
        .task { runRecovery() }
        // 待裁决的草稿逐个问。一次问一份，问得清楚，也免得用户为了关掉弹窗胡乱点。
        .alert("有一笔没记上", isPresented: .constant(!recovery.pending.isEmpty)) {
            Button("记上") { accept() }
            Button("不记了", role: .destructive) { discard() }
        } message: {
            Text(recovery.pending.first.map(Self.recoveryMessage) ?? "")
        }
        .alert("出了点问题", isPresented: .constant(failure != nil)) {
            Button("知道了") { failure = nil }
        } message: { Text(failure ?? "") }
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
            ItemEditorView(vm: ItemEditorViewModel(
                store: env.items,
                editing: id.flatMap { try? env.items.item(id: $0) }
            ))
        }
    }

    private func runRecovery() {
        do {
            try recovery.runAtLaunch()
            try today.reload(dayStartHour: env.settings.dayStartHour)
        } catch { failure = error.localizedDescription }
    }

    private func accept() {
        guard let first = recovery.pending.first else { return }
        do {
            try recovery.accept(first)
            try today.reload(dayStartHour: env.settings.dayStartHour)
        } catch { failure = error.localizedDescription }
    }

    private func discard() {
        guard let first = recovery.pending.first else { return }
        do {
            try recovery.discard(first)
            try today.reload(dayStartHour: env.settings.dayStartHour)
        } catch { failure = error.localizedDescription }
    }

    private func reloadToday() {
        do { try today.reload(dayStartHour: env.settings.dayStartHour) }
        catch { failure = error.localizedDescription }
    }
}
