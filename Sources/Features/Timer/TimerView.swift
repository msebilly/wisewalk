import SwiftUI

/// §6.3 计时器。
///
/// **界面上的每秒刷新只负责显示**：真正的时长永远是 `now − startedAt` 现算。
/// 靠 `Timer` 累加的做法在 App 挂起时会停摆，用户打坐半小时回来只记到几秒——
/// 而这是个只增不减的账本，少记了就得靠补记来擦屁股。
///
/// 屏幕常亮：打坐时屏幕本该熄掉，但一熄用户就看不到走时。折中是**不强制常亮**，
/// 时长靠时间戳，熄屏不影响正确性。
struct TimerView: View {
    @Bindable var vm: TimerViewModel
    let settings: AppSettings
    let onFinish: () -> Void

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var failure: String?
    /// 返回时这一坐太短，正在问「记上还是放弃」。
    @State private var confirmingShortExit = false
    /// 计时器读数不像真的，正在问实际坐了多久。0 表示没在问。
    @State private var implausibleReading = 0
    @State private var correctHours = 0
    @State private var correctMinutes = 0

    /// 短于这个数的一坐，返回时要问一句。
    ///
    /// 一分钟这个界不是随手定的：真坐的人不会只坐几十秒，而在今日页点错行、
    /// 进来一看不对就退出去，恰恰全落在这个区间里。
    static let confirmExitBelow = 60

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            theme.background
            VStack(spacing: 12) {
                Text(vm.clockText)
                    .font(.system(size: 72, weight: .light, design: .rounded).monospacedDigit())
                    .foregroundStyle(theme.primaryText)
                Text(subtitle)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) { controls }
        .navigationTitle(vm.item.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { try vm.start(dayStartHour: settings.dayStartHour) }
            catch { failure = error.localizedDescription }
        }
        .onReceive(tick) { now in
            vm.refresh(at: now)
            // 心跳每 10 秒落一次盘。**但这个 tick 一进后台就停**
            //（Timer.publish 在 .common 上也救不了挂起），所以「最坏少记 10 秒」
            // 只在 App 停在前台时成立。锁屏放一边坐半小时、期间被系统回收，
            // 恢复时能捞回来的就只有锁屏前那十几秒。见 TimerViewModel
            // heartbeatInterval 的注释。
            do { try vm.heartbeatIfNeeded(at: now) }
            catch { failure = error.localizedDescription }
        }
        // 回到前台走一遍 start()，而不只是 refresh()。
        // 熄屏期间日子可能翻过去了，别的设备也可能同步进来一坐；
        // refresh() 只重算本轮秒数，committedTotal 还是熄屏前那个数。
        // start() 是幂等的（沿用同一份草稿、startedAt 从草稿读回来、
        // committedTotal 是赋值不是累加），拿它当 reload 正合适。
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            do { try vm.start(dayStartHour: settings.dayStartHour) }
            catch { failure = error.localizedDescription }
        }
        // 兜底：任何绕过返回键的收页路径（父视图程序化 dismiss 等）也要把账记上。
        // 走 leave() 出去的两条路都已经把 draft 清空，这里再调是空操作。
        .onDisappear { commit() }
        // 换自己的返回键，为的是能在收页**之前**问那一句。
        // 代价是失去右滑返回手势——计时页上这个代价划算：这一页本来就该是
        // 「进来了就好好坐」，误触右滑而多记一坐比少一个手势糟得多。
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { leave() } label: {
                    Label("返回", systemImage: "chevron.backward")
                }
            }
        }
        .confirmationDialog("这一坐只有 \(DurationFormat.spoken(vm.elapsed))",
                            isPresented: $confirmingShortExit, titleVisibility: .visible) {
            Button("记上") { commitAndLeave() }
            Button("放弃这一坐", role: .destructive) { abandonAndLeave() }
            Button("接着坐", role: .cancel) {}
        } message: {
            Text("是刚才点错了，还是真的坐了这么久？")
        }
        .sheet(isPresented: Binding(get: { implausibleReading > 0 },
                                    set: { if !$0 { implausibleReading = 0 } })) {
            correctionSheet
        }
        .alert("出了点问题", isPresented: .constant(failure != nil)) {
            Button("知道了") { failure = nil }
        } message: { Text(failure ?? "") }
    }

    /// 计时器读数过长时问用户实际坐了多久。
    ///
    /// **不预填任何数**。预填等于替用户编一个数，而他多半会顺手确认。
    /// 读数照实说出来（「计时器上是 8 小时」），但它只是线索不是答案。
    private var correctionSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Picker("小时", selection: $correctHours) {
                            ForEach(0..<24, id: \.self) { Text("\($0) 小时").tag($0) }
                        }
                        Picker("分钟", selection: $correctMinutes) {
                            ForEach(0..<60, id: \.self) { Text("\($0) 分").tag($0) }
                        }
                    }
                    .pickerStyle(.wheel)
                } header: {
                    Text("实际坐了多久")
                } footer: {
                    Text("计时器上是 \(DurationFormat.spoken(implausibleReading))，多半是忘了按结束。填多少就记多少，这个数不会替你猜。")
                }
            }
            .navigationTitle("这一坐记多少")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("放弃这一坐", role: .destructive) {
                        implausibleReading = 0
                        abandonAndLeave()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("记上") {
                        let seconds = DurationField.seconds(hours: correctHours, minutes: correctMinutes)
                        implausibleReading = 0
                        do {
                            _ = try vm.record(seconds: seconds)
                        } catch {
                            failure = error.localizedDescription
                            return
                        }
                        onFinish()
                        dismiss()
                    }
                    .disabled(DurationField.seconds(hours: correctHours, minutes: correctMinutes) == 0)
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private var controls: some View {
        Button {
            // 主动按「结束并记录」是明确的收坐意思，不问短不短。
            commitAndLeave()
        } label: {
            Text("结束并记录")
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// 副标题：今日已记时长，外加**今天是第几坐**。
    ///
    /// 「时间和坐数量」是用户点名要的两个数。坐数在这一页尤其有用——
    /// 早课坐一回、晚课坐一回，只看总时长分不出是坐了两回还是一回坐了两倍长。
    /// 本轮还没记上，所以说的是「今日 N 坐」，收坐之后才 +1。
    private var subtitle: String {
        let progress = FulfillmentBadge.progressText(total: vm.dayTotal, goal: vm.item.dailyGoal,
                                                     unit: vm.item.unit, measureType: vm.item.measureType)
        guard vm.dayRounds > 0 else { return progress }
        return "\(progress) · 今日 \(vm.dayRounds) 坐"
    }

    /// 返回。不足一分钟先问一句，够长的直接记。
    private func leave() {
        if vm.elapsed > 0 && vm.elapsed < Self.confirmExitBelow {
            confirmingShortExit = true
        } else {
            commitAndLeave()
        }
    }

    private func commitAndLeave() {
        // 记上了才收页。从前是记账失败也照样 onFinish() + dismiss()，
        // 页面在 alert 来得及呈现之前就消失了，用户看着页面收起、以为记上了。
        // 那是**假确认**，比直接报错更坏。
        guard commit() else { return }
        onFinish()
        dismiss()
    }

    private func abandonAndLeave() {
        do { try vm.abandon() }
        catch { failure = error.localizedDescription; return }
        onFinish()
        dismiss()
    }

    /// 记账。**成功才返回 true**，调用方据此决定要不要收页。
    ///
    /// 读数超过 4 小时时不落账、草稿原样留着，转而弹出来问实际时长——
    /// 此时返回 false，页面留在原地。
    @discardableResult
    private func commit() -> Bool {
        do {
            _ = try vm.finish()
            return true
        } catch TimerViewModelError.implausibleDuration(let seconds) {
            correctHours = 0
            correctMinutes = 0
            implausibleReading = seconds
            return false
        } catch {
            failure = error.localizedDescription
            return false
        }
    }
}
