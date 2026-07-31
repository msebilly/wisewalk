import SwiftUI

/// §6.2 计数器。
///
/// **点击区与控件区严格分层**：计数区放在 `safeAreaInset` 之上，控件条放在
/// `safeAreaInset(edge: .bottom)` 里——两者在布局上就不重叠，
/// 不是靠 z 序压住。压住的做法只要有一处 padding 算错就会漏点进去，
/// 而「点返回却多记了一下」在竞品差评里是出现过的。
struct CounterView: View {
    @Bindable var vm: CounterViewModel
    let settings: AppSettings
    /// 由父视图负责收起本页。
    let onFinish: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showBatch = false
    @State private var batchStep = TemplateCatalog.defaultBatchStep
    @State private var failure: String?

    /// 大号数字。**不带千分位分组符号**——分组符号宽度与数字不同，
    /// 跨过 999→1000 时整行会跳一下，正是 `.monospacedDigit()` 要治的毛病。
    static func bigNumberText(_ n: Int) -> String { String(n) }

    var body: some View {
        countingSurface
            .safeAreaInset(edge: .bottom) { controls }
            .navigationTitle(vm.item.name)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                do {
                    try vm.start(dayStartHour: settings.dayStartHour)
                    Feedback.shared.prepare()
                } catch { failure = error.localizedDescription }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                // 熄屏一夜再回来，日子可能已经翻过去了，别处记的流水也可能同步进来，
                // 而 `committedTotal` 是**进页面那一刻那一天**的数。
                // 不重读就会拿昨天的数当「今日已记」——屏幕替用户多报一整天。
                //
                // `start()` 幂等：草稿沿用、已经念的不清零，只把「今日已记」重读一遍
                // （`回到前台重新start会重读今日已记且不清零` 钉住了这一点）。
                do { try vm.start(dayStartHour: settings.dayStartHour) }
                catch { failure = error.localizedDescription }
                // `prepare()` 不留「配过了」的闩，所以回前台重来一次是安全的，
                // 而且必要：通话中 `setCategory` 会失败，那一次失败不该跟着用户一整坐。
                Feedback.shared.prepare()
            }
            .onDisappear { commit() }
            .sheet(isPresented: $showBatch) {
                BatchSheet(step: $batchStep) {
                    vm.setBatchStep(batchStep)
                    perform { try vm.addBatch() }
                }
            }
            .alert("出了点问题", isPresented: .constant(failure != nil)) {
                Button("知道了") { failure = nil }
            } message: { Text(failure ?? "") }
    }

    /// 整屏可点。竞品缩小点击区后被明确差评，这是刚需。
    private var countingSurface: some View {
        ZStack {
            theme.background
            VStack(spacing: 10) {
                Text(Self.bigNumberText(vm.dayTotal))
                    .font(.system(size: 84, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.primaryText)
                    .contentTransition(.numericText())
                Text(subtitle)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
                if vm.count > 0 {
                    Text("本次 \(vm.count)")
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(theme.tertiaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { perform { try vm.tap() } }
        .onLongPressGesture(minimumDuration: 0.5) {
            batchStep = vm.batchStep
            showBatch = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("计数区")
        .accessibilityValue(subtitle)
        .accessibilityHint("轻点加一，长按批量增加")
        .accessibilityAddTraits(.isButton)
    }

    /// 结束与撤销。**不在计数区内**。
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                perform { try vm.undo() }
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.bordered)
            .disabled(vm.count == 0)

            Spacer()

            Button {
                // 记上了才收页。从前是记账失败也照样 onFinish() + dismiss()，
                // 页面在 alert 来得及呈现之前就消失了，用户看着页面收起、
                // 以为记上了。那是**假确认**，比直接报错更坏。
                guard commit() else { return }
                onFinish()
                dismiss()
            } label: {
                Text("结束并记录")
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private var subtitle: String {
        FulfillmentBadge.progressText(total: vm.dayTotal, goal: vm.item.dailyGoal,
                                      unit: vm.item.unit, measureType: vm.item.measureType)
    }

    /// 每一次记数都给反馈。§6.2：这是**防漏记多记的功能性反馈，不是装饰**——
    /// 念珠有手感，屏幕没有，用户需要一个「刚才那下算上了」的确认。
    ///
    /// 正因为它是确认，**只有真记上了才许响**。`vm.tap()` 在没有草稿时会抛
    /// `.notCounting`（`start()` 抛过错、页面还在、整屏还可点，这条路够得着），
    /// 走 catch、不走 tick。闭着眼睛靠声音数数的人分辨不出「响了但没记上」。
    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            Feedback.shared.tick(sound: settings.soundEnabled, haptic: settings.hapticEnabled)
        } catch {
            failure = error.localizedDescription
        }
    }

    /// 记账。**成功才返回 true**，调用方据此决定要不要收页。
    ///
    /// 幂等：`onDisappear` 与「结束并记录」都会调，`finish()` 里 `draft` 已清空则直接返回 nil。
    @discardableResult
    private func commit() -> Bool {
        do { _ = try vm.finish(); return true }
        catch { failure = error.localizedDescription; return false }
    }
}
