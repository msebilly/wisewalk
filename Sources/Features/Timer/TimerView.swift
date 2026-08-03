import SwiftUI
import AVFoundation
import UIKit

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

    /// 是否已经起坐。未起坐时显示档位选择，起坐后显示走时。
    @State private var started = false
    /// 选中的倒计时秒数。`nil` = 不限时（正计时）。
    @State private var chosenCountdown: Int?
    /// 自定义时长选择器是否打开。
    @State private var choosingCustom = false
    @State private var customHours = 0
    @State private var customMinutes = 30
    /// 前台到零响引磬的播放器。**必须持有**：局部变量会在闭包结束时释放，声音随之截断。
    @State private var qingPlayer: AVAudioPlayer?
    /// 本页是否已经问过通知权限。问过就不再问——被拒之后每选一档弹一次是骚扰。
    @State private var qingAuthorizationAsked = false
    /// 通知权限被拒，正在告诉用户「锁屏时不会响」。
    @State private var lockScreenSilent = false

    /// 短于这个数的一坐，返回时要问一句。
    ///
    /// 一分钟这个界不是随手定的：真坐的人不会只坐几十秒，而在今日页点错行、
    /// 进来一看不对就退出去，恰恰全落在这个区间里。
    static let confirmExitBelow = 60

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            theme.background
            if started {
                running
            } else {
                chooser
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle(vm.item.name)
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(tick) { now in
            guard started else { return }
            vm.refresh(at: now)
            // 心跳每 10 秒落一次盘。**但这个 tick 一进后台就停**
            //（Timer.publish 在 .common 上也救不了挂起），所以「最坏少记 10 秒」
            // 只在 App 停在前台时成立。锁屏放一边坐半小时、期间被系统回收，
            // 恢复时能捞回来的就只有锁屏前那十几秒。见 TimerViewModel
            // heartbeatInterval 的注释。
            do { try vm.heartbeatIfNeeded(at: now) }
            catch { failure = error.localizedDescription }
        }
        // 前台到零响一声引磬，只在 false → true 那一次——别每秒 tick 都响。
        // 账绝不依赖它：走时与入账全由 now − startedAt 现算，与响没响无关。
        .onChange(of: vm.hasReachedZero) { wasZero, isZero in
            guard !wasZero, isZero else { return }
            ringQing()
        }
        // 回到前台走一遍 start()，而不只是 refresh()。
        // 熄屏期间日子可能翻过去了，别的设备也可能同步进来一坐；
        // refresh() 只重算本轮秒数，committedTotal 还是熄屏前那个数。
        // start() 是幂等的（沿用同一份草稿、startedAt 从草稿读回来、
        // committedTotal 是赋值不是累加），拿它当 reload 正合适。
        // **未起坐时不走**：否则回前台会把还在选档位的用户偷偷带进计时。
        .onChange(of: scenePhase) { _, phase in
            guard started, phase == .active else { return }
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
        .alert("出了点问题", isPresented: .presenting($failure)) {
            Button("知道了") { failure = nil }
        } message: { Text(failure ?? "") }
        // 降级要说出来。不吭声的降级会让他以为倒计时在替他守着。
        .alert("锁屏时不会响", isPresented: $lockScreenSilent) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("没给通知权限，引磬只在 App 开着、屏幕亮着的时候响。走时和记录不受影响，一秒都不会少。想让它锁屏也响，到「设置 › 通知 › 慧行」里打开。")
        }
    }

    /// 走时与今日进度，起坐后显示。
    private var running: some View {
        VStack(spacing: 12) {
            Text(vm.clockText)
                .font(.system(size: 72, weight: .light, design: .rounded).monospacedDigit())
                .foregroundStyle(theme.primaryText)
            Text(subtitle)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.secondaryText)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("走时")
        .accessibilityValue(Self.spokenValue(clock: vm.clockText, subtitle: subtitle))
    }

    /// 起坐前的倒计时档位选择。§6.3.1。
    ///
    /// **没有「一炷香」这一档**——见 `TimerViewModel.countdownChoices` 的注释。
    private var chooser: some View {
        Form {
            Section {
                ForEach(TimerViewModel.countdownChoices, id: \.self) { seconds in
                    choiceRow(choiceLabel(seconds), selected: chosenCountdown == seconds) {
                        chosenCountdown = seconds
                        ensureQingAuthorization()
                    }
                }
                choiceRow("不限时", selected: chosenCountdown == nil) {
                    chosenCountdown = nil
                }
                Button { choosingCustom = true } label: {
                    HStack {
                        Text("自定义")
                            .foregroundStyle(theme.primaryText)
                        Spacer()
                        if isCustomSelection {
                            Text(DurationFormat.spoken(chosenCountdown ?? 0))
                                .foregroundStyle(theme.secondaryText)
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.accent)
                        }
                    }
                }
            } header: {
                Text("倒计时")
            } footer: {
                Text("到时响一声引磬提醒下坐。到零后走时钉在这里，不会替你多记一秒。")
            }
        }
        .sheet(isPresented: $choosingCustom) { customSheet }
    }

    /// 底部主按钮：起坐后是「结束并记录」，起坐前是「开始」。
    @ViewBuilder private var bottomBar: some View {
        if started {
            controls
        } else {
            Button {
                vm.setCountdown(chosenCountdown)
                do {
                    try vm.start(dayStartHour: settings.dayStartHour)
                    // 按**剩余**排，不是按整段排。`start()` 会照单全收旧草稿
                    // （杀进程后重开、挂起再回来都走这条路），此刻 `elapsed` 已经不是 0。
                    // 按整段排的话：设 30 分钟、坐了 10 分钟被杀、重开接着坐，
                    // 到零在 20 分钟后而引磬在 30 分钟后——**用户多坐了 10 分钟**，
                    // 而让他多坐的正是这个 App。
                    //
                    // 账本不受影响（§6.3.1 定案一：到零钉死在到零那一刻，不入账），
                    // 但「引磬只是尽量响」说的是响不响，不是可以响错时候。
                    if let seconds = vm.countdownSeconds {
                        let remaining = seconds - vm.elapsed
                        if remaining > 0 {
                            QingScheduler.schedule(after: remaining, itemName: vm.item.name,
                                                   sound: settings.qingEnabled)
                        } else {
                            QingScheduler.cancel()
                        }
                    }
                } catch {
                    failure = error.localizedDescription
                    return
                }
                started = true
            } label: {
                Text(startTitle)
                    .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
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
            // §6.2 的暖底一直没盖到 sheet 上：实测模板 sheet 底是 (242,242,247)
            // 也就是系统 `#F2F2F7`，而全 App 的底是 `#FAF7F0` (250,247,240)——
            // **一个偏蓝一个偏黄，冷暖是反的**，翻到这一页突然凉一下。
            // 挂在 Form/List 上而不是 NavigationStack 外面：后者自己画一层不透明系统底，
            // 挂外面会被它整个盖住。
            .pageBackground()
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
                        QingScheduler.cancel()
                        onFinish()
                        dismiss()
                    }
                    .disabled(DurationField.seconds(hours: correctHours, minutes: correctMinutes) == 0)
                }
            }
            .interactiveDismissDisabled()
        }
    }

    /// 自定义倒计时时长。走与纠正读数相同的时分转盘。
    private var customSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 0) {
                        Picker("小时", selection: $customHours) {
                            ForEach(0..<5, id: \.self) { Text("\($0) 小时").tag($0) }
                        }
                        Picker("分钟", selection: $customMinutes) {
                            ForEach(0..<60, id: \.self) { Text("\($0) 分").tag($0) }
                        }
                    }
                    .pickerStyle(.wheel)
                } header: {
                    Text("倒计时多久")
                } footer: {
                    Text("超过四小时会被当成忘按结束，选不了。")
                }
            }
            .pageBackground()
            .navigationTitle("自定义倒计时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { choosingCustom = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        chosenCountdown = DurationField.seconds(hours: customHours, minutes: customMinutes)
                        choosingCustom = false
                        ensureQingAuthorization()
                    }
                    .disabled(!customIsValid)
                }
            }
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

    /// 起坐按钮上的文字。选了倒计时就把时长报出来，没选就是「开始」。
    private var startTitle: String {
        guard let seconds = chosenCountdown else { return "开始" }
        return "开始 · \(DurationFormat.spoken(seconds))"
    }

    /// 当前选中的是一个自定义值（既不是预设档位，也不是「不限时」）。
    private var isCustomSelection: Bool {
        guard let seconds = chosenCountdown else { return false }
        return !TimerViewModel.countdownChoices.contains(seconds)
    }

    /// 自定义时长在闸门之内才可确定。四小时整可以，多一秒起坐必被拦。
    private var customIsValid: Bool {
        let seconds = DurationField.seconds(hours: customHours, minutes: customMinutes)
        return seconds > 0 && TimeInterval(seconds) <= TimerViewModel.implausibleAfter
    }

    /// 档位文字。§6.3.1：一律用分钟数直呼，不贴「一炷香」这类编出来的标签。
    private func choiceLabel(_ seconds: Int) -> String { DurationFormat.spoken(seconds) }

    private func choiceRow(_ label: String, selected: Bool,
                           _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(theme.primaryText)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(theme.accent)
                }
            }
        }
    }

    /// 副标题：今日已记时长，外加**今天是第几坐**。
    ///
    /// 「时间和坐数量」是用户点名要的两个数。坐数在这一页尤其有用——
    /// 早课坐一回、晚课坐一回，只看总时长分不出是坐了两回还是一回坐了两倍长。
    /// 本轮还没记上，说的是收坐之前的坐数，收坐之后才 +1。
    private var subtitle: String {
        Self.subtitleText(dayTotal: vm.dayTotal, goal: vm.item.dailyGoal,
                          unit: vm.item.unit, measureType: vm.item.measureType,
                          rounds: vm.dayRounds)
    }

    /// **「今日」两个字不能省。** 这一页摞着两个 `H:MM`：大号是本轮走时，
    /// 小号是今日已记。当天头一坐时两者恒等（今日 = 0 + 本轮），
    /// 同一个数印了两遍；第二坐起才分家，而那时用户没有任何依据判断哪个是哪个。
    ///
    /// 计数器页早把这件事做对了：大号是今日，本轮另配「本次 N」的标签。
    /// 这一页把两个数对调了，标签却没跟着搬过来。
    ///
    /// 「· N 坐」的拼法交给 `progressText`，这里不再拼第二遍——
    /// 拼两遍就会有两种说法（本仓库为此栽过三次）。
    nonisolated static func subtitleText(dayTotal: Int, goal: Int?, unit: String,
                                         measureType: MeasureType, rounds: Int) -> String {
        "今日 " + FulfillmentBadge.progressText(total: dayTotal, goal: goal, unit: unit,
                                               measureType: measureType, rounds: rounds)
    }

    /// 读屏软件听到的那一句。
    ///
    /// 这一页从前**零无障碍标注**，于是 VoiceOver 把两个 `Text` 念成两个赤裸的时刻
    /// （「十比零零」「四十比零零」），看不见屏幕的人分不出哪个是哪个——
    /// 而这两个数正是他唯一能拿到的信息。
    nonisolated static func spokenValue(clock: String, subtitle: String) -> String {
        "本次 \(clock)，\(subtitle)"
    }

    /// 通知权限延后到**用户第一次真的设倒计时**这一刻才要。§6.3.1 定案二。
    ///
    /// 不在启动时问：从不用倒计时的人不该为一个他不用的功能被弹窗打扰，
    /// 而在他要用的那一刻问，他也才知道这个权限是干什么的。
    ///
    /// 被拒绝就**当场**告诉他锁屏时不会响——不能让他锁屏坐完一坐、
    /// 下坐才发现引磬没响。降级本身不是问题，**不吭声的降级才是**：
    /// 他会以为自己设的倒计时在替他守着。
    ///
    /// 问过一次就不再问：拒绝之后每选一档弹一次是骚扰，而系统那边也只会给
    /// 第一次真弹窗，之后 `requestAuthorization` 直接返回存着的那个答案。
    ///
    /// 「锁屏时不会响」这句话**落盘记一次说过没有**，而不是靠这个 `@State`：
    /// 页面每次进来都是新的，只靠它等于每坐一次弹一遍。
    private func ensureQingAuthorization() {
        guard !qingAuthorizationAsked else { return }
        qingAuthorizationAsked = true
        Task {
            guard await QingScheduler.requestAuthorization() == false else { return }
            guard !settings.qingLockScreenNoticed else { return }
            settings.qingLockScreenNoticed = true
            lockScreenSilent = true
        }
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
        QingScheduler.cancel()
        onFinish()
        dismiss()
    }

    /// 前台到零响一声引磬，并同时震动。
    ///
    /// 前台走 `AVAudioPlayer` + `.ambient`：媒体音量、跟随物理静音键、且不掐断念佛机。
    /// 震动是静音键拨上时**唯一**的信号，所以只要引磬功能开着就震——哪怕没出声。
    private func ringQing() {
        guard settings.qingEnabled else { return }
        try? AVAudioSession.sharedInstance()
            .setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        qingPlayer = try? AVAudioPlayer(data: QingSound.wavData())
        qingPlayer?.play()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 记账。**成功才返回 true**，调用方据此决定要不要收页。
    ///
    /// 读数超过 4 小时时不落账、草稿原样留着，转而弹出来问实际时长——
    /// 此时返回 false，页面留在原地。
    @discardableResult
    private func commit() -> Bool {
        do {
            _ = try vm.finish()
            QingScheduler.cancel()
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
