import SwiftUI

/// 一条流水在界面上的说法。
enum EntryRow {
    static func isRevocation(_ s: PracticeSession) -> Bool {
        s.note?.hasPrefix("revoke:") == true
    }

    static func isMigration(_ s: PracticeSession) -> Bool {
        s.note == ManualEntryViewModel.migrationNote
    }

    /// 数量的说法。计时类按时长说——「+1800」对打坐是没有意义的数字。
    static func amountText(_ s: PracticeSession, item: PracticeItem?) -> String {
        // 用真的减号 U+2212 而不是连字符：等宽数字下连字符太短，
        // 一列流水里正负号高低不齐，扫一眼看不出哪笔是撤销。
        let sign = s.amount < 0 ? "\u{2212}" : "+"
        let magnitude = abs(s.amount)
        switch item?.measureType {
        case .duration:
            return "\(sign)\(DurationFormat.spoken(magnitude))"
        case .check:
            return s.amount < 0 ? "取消" : "已完成"
        default:
            let unit = item?.unit ?? ""
            return unit.isEmpty ? "\(sign)\(magnitude)" : "\(sign)\(magnitude) \(unit)"
        }
    }

    static func sourceText(_ s: PracticeSession) -> String {
        if isMigration(s) { return "历史累计" }
        if isRevocation(s) { return "撤销" }
        switch s.source {
        case .counter: return "计数器"
        case .timer: return "计时器"
        case .manual: return "手动补记"
        case .adjustment: return "修正"
        }
    }

    static func timeText(_ s: PracticeSession) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "HH:mm"
        f.timeZone = TimeZone(secondsFromGMT: s.tzOffsetMinutes * 60) ?? .current
        return f.string(from: s.createdAt)
    }
}

/// §6.4 补记与修正。
///
/// **修正区是并列的一等区域**，不是藏在二级菜单里的高级功能——
/// 竞品差评证明「改错数字找不到入口」是真实痛点。
struct ManualEntryView: View {
    @Bindable var vm: ManualEntryViewModel
    let settings: AppSettings

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var pickedDate = Date()
    @State private var hours = 0
    @State private var minutes = 0
    @State private var entries: [PracticeSession] = []
    @State private var showMigration = false
    @State private var failure: String?
    @State private var toast: String?

    // 不自己判断「是不是计时类」——去问 `AmountInputStyle`。
    // 从前这一句是本页私有的，而迁移页压根没写这一句，于是那边问出了裸秒（3600 倍）。
    private var isDuration: Bool {
        AmountInputStyle.forMeasure(vm.selectedItem?.measureType) == .duration
    }
    private var today: Int { DayKey.today(dayStartHour: settings.dayStartHour) }

    var body: some View {
        Form {
            entrySection
            correctionSection
            migrationSection
        }
        .navigationTitle("补记")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .onChange(of: hours) { _, _ in syncDial() }
        .onChange(of: minutes) { _, _ in syncDial() }
        .alert("出了点问题", isPresented: .presenting($failure)) {
            Button("知道了") { failure = nil }
        } message: { Text(failure ?? "") }
        .alert("记上了", isPresented: .presenting($toast)) {
            Button("好") { toast = nil }
        } message: { Text(toast ?? "") }
        .sheet(isPresented: $showMigration) {
            MigrationSheet(vm: vm, settings: settings) { load() }
        }
    }

    private var entrySection: some View {
        Section("补记一笔") {
            Picker("功课", selection: $vm.selectedItem) {
                ForEach(vm.pickerItems) { item in
                    Text(item.name).tag(Optional(item))
                }
            }
            .onChange(of: vm.selectedItem?.id) { _, _ in
                // 换了功课就把输入清空。留着上一门课的数**等于替用户编一个数**：
                // 刚在「打坐」转盘上拨到 30 分（`vm.amount` = 1800），一改选「念佛」，
                // 数量框里赫然是 1800，顺手一点「记上」就是 1800 声。
                resetInput()
                refreshEntries()
            }

            DatePicker("日期", selection: $pickedDate,
                       in: ...Date(), displayedComponents: .date)
                .onChange(of: pickedDate) { _, d in
                    vm.selectedDayKey = DayKey.fromCalendarDate(d)
                    refreshEntries()
                }

            if isDuration {
                Picker("小时", selection: $hours) {
                    ForEach(0..<24, id: \.self) { Text("\($0)") }
                }
                Picker("分钟", selection: $minutes) {
                    ForEach(0..<60, id: \.self) { Text("\($0)") }
                }
            } else {
                HStack {
                    Text("数量")
                    Spacer()
                    TextField("0", text: $vm.amount.numericText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit())
                        .frame(maxWidth: 120)
                }
            }

            TextField("备注（可不填）", text: $vm.note)

            Button("记上") { submit() }
                .disabled(!canSubmit)
        }
    }

    /// **修正区**。§6.4：入口必须显眼，所以它就在补记的正下方，不折叠、不藏。
    private var correctionSection: some View {
        Section {
            if entries.isEmpty {
                Text("这一天还没有记录")
                    .font(.subheadline)
                    .foregroundStyle(theme.tertiaryText)
            } else {
                ForEach(entries) { s in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(EntryRow.amountText(s, item: vm.selectedItem))
                                .font(.body.monospacedDigit())
                                .foregroundStyle(s.amount < 0 ? theme.tertiaryText : theme.primaryText)
                            Text("\(EntryRow.timeText(s)) · \(EntryRow.sourceText(s)) · \(s.deviceName)")
                                .font(.caption)
                                .foregroundStyle(theme.tertiaryText)
                        }
                        Spacer()
                        if !EntryRow.isRevocation(s) {
                            Button("撤销") { revoke(s) }
                                .buttonStyle(.bordered)
                                .font(.footnote)
                        }
                    }
                }
            }
        } header: {
            Text("这一天的记录 · 记错了在这里改")
        } footer: {
            // 用户会怕「撤销」是删掉证据。说清楚它不是。
            Text("撤销不会删掉原记录，而是补一笔相反的账，来龙去脉都留着。")
        }
    }

    private var migrationSection: some View {
        Section {
            Button("记入以往的累计") { showMigration = true }
        } footer: {
            Text("把纸本或别的应用里已有的累计数一次性记进来，只需做一次。")
        }
    }

    /// ⛔ **这里从前带一句 `if isDuration { vm.amount = … }`。**
    ///
    /// 它是被 `.disabled(!canSubmit)` 在 `body` 求值途中调用的，而 `vm.canSubmit()`
    /// 经 `validate` 又读 `vm.amount`——同一趟 `body` 里对一个 `@Observable`
    /// 属性既读又写。`@Observable` 生成的 setter 不比较新旧值，写进去就发通知，
    /// 于是写 → 失效 → 重绘 → 再写。**计时类功课（打坐）一被选中，补记页就卡在
    /// 重绘里出不来**，而视图层一条测试都覆盖不到它。
    ///
    /// 转盘的值改由 `body` 上那两个 `.onChange` 推进去，与 `pickedDate` 同一个写法。
    private var canSubmit: Bool { vm.canSubmit() }

    /// 转盘 → `vm.amount`。只有计时类用得上；计数类的数量直接绑在 `$vm.amount` 上。
    private func syncDial() {
        guard isDuration else { return }
        vm.amount = DurationField.seconds(hours: hours, minutes: minutes)
    }

    /// 清空这张表单上用户填的数，不动选中的功课和日期。
    private func resetInput() {
        vm.amount = 0
        hours = 0
        minutes = 0
    }

    private func load() {
        do {
            try vm.reloadItems()
            vm.selectedDayKey = today
            pickedDate = DayKey.calendarDate(of: today) ?? Date()
            refreshEntries()
        } catch { failure = error.localizedDescription }
    }

    private func refreshEntries() {
        guard let item = vm.selectedItem else { entries = []; return }
        do { entries = try vm.entries(on: vm.selectedDayKey, itemID: item.id) }
        catch { failure = error.localizedDescription }
    }

    private func submit() {
        syncDial()
        do {
            let s = try vm.submit()
            toast = EntryRow.amountText(s, item: vm.selectedItem)
            // `vm.amount` / `vm.note` 由 `submit()` 自己清（它得防连点两下），
            // 这里只清本视图自己的转盘。
            hours = 0
            minutes = 0
            refreshEntries()
        } catch { failure = error.localizedDescription }
    }

    private func revoke(_ s: PracticeSession) {
        do {
            try vm.revoke(s)
            refreshEntries()
        } catch { failure = error.localizedDescription }
    }
}

/// §6.12 迁移。单独一层，免得与日常补记混淆——
/// 这是**只做一次**的动作，混在一起会有人天天点。
struct MigrationSheet: View {
    @Bindable var vm: ManualEntryViewModel
    let settings: AppSettings
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var failure: String?
    /// 计时类专用。见下面 `isDuration` 那一段。
    @State private var hours = 0
    @State private var minutes = 0

    private var isDuration: Bool {
        AmountInputStyle.forMeasure(vm.selectedItem?.measureType) == .duration
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("功课", selection: $vm.selectedItem) {
                        ForEach(vm.pickerItems) { item in
                            Text(item.name).tag(Optional(item))
                        }
                    }
                    HStack {
                        Text("以往累计")
                        Spacer()
                        if isDuration {
                            // ⛔ **不能照抄补记页的 24 小时转盘。** 这里装的是他一辈子的功课，
                            // 「打坐累计三千小时」是很正常的一个数，转盘转不到。
                            //
                            // 旁边那两个「小时」「分」是独立的 `Text`，读屏软件不会把它们
                            // 和框关联起来——不写 label，VoiceOver 念到这儿只有孤零零一个
                            // 「0」，用户不知道该往哪个填。面向老居士的 App 尤其不能这样。
                            TextField("0", text: $hours.numericText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.body.monospacedDigit())
                                .frame(maxWidth: 90)
                                .accessibilityLabel("小时")
                            Text("小时")
                            TextField("0", text: $minutes.numericText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.body.monospacedDigit())
                                .frame(maxWidth: 50)
                                .accessibilityLabel("分钟")
                            Text("分")
                        } else {
                            TextField("0", text: $vm.amount.numericText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .font(.body.monospacedDigit())
                                .frame(maxWidth: 140)
                                .accessibilityLabel("以往累计")
                        }
                    }
                } footer: {
                    Text("会记成一笔单独的账，注明是以往累计，不会与日后的功课混在一起。只需做一次。")
                }
            }
            .navigationTitle("记入以往的累计")
            .navigationBarTitleDisplayMode(.inline)
            // ⛔ 这张表和补记表单共用同一个 `vm`，**每个可变字段都得进出各擦一次**。
            // 借还收在 `beginMigration()` / `endMigration()` 里，不散在这几个闭包上——
            // 散着写就得说好几遍，而第一版正是这么写的，于是擦了 `amount`、
            // 漏了 `selectedItem`：用户在补记页选好「念佛」，进来改选「持咒」再按取消，
            // 退回去选择器停在「持咒」，一点「记上」这笔就记到持咒头上。
            .onAppear {
                vm.beginMigration()
                hours = 0
                minutes = 0
            }
            // ⛔ 转盘的值**只能从这里推进 `vm.amount`**，绝不能在 `body` 里写——
            // 下面「记上」的 `.disabled(!vm.canSubmit())` 会在同一趟 `body` 里读它，
            // 而 `@Observable` 的 setter 不比较新旧值，写进去就发通知：
            // 写 → 失效 → 重绘 → 再写，选中打坐这张表就卡死了。
            // 补记页为这一条踩过一次坑，注释在 `canSubmit` 上面。
            .onChange(of: hours) { _, _ in syncDial() }
            .onChange(of: minutes) { _, _ in syncDial() }
            .onChange(of: vm.selectedItem?.id) { _, _ in
                // 换了功课就清空。不清的话，在「打坐」填了 3000（小时→秒是 1080 万）
                // 改选「念佛」，这个数会原样留在 `vm.amount` 里，
                // 一点「记上」就是**一千零八十万声**。语义变了，数就不能留。
                vm.amount = 0
                hours = 0
                minutes = 0
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { vm.endMigration(); dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("记上") { submit() }
                        .disabled(!vm.canSubmit())
                }
            }
            .alert("出了点问题", isPresented: .presenting($failure)) {
                Button("知道了") { failure = nil }
            } message: { Text(failure ?? "") }
        }
        .presentationDetents([.medium])
    }

    private func syncDial() {
        guard isDuration else { return }
        vm.amount = DurationField.seconds(hours: hours, minutes: minutes)
    }

    private func submit() {
        do {
            _ = try vm.submitMigrationTotal()
            // 成功也要还——「记上」和「取消」两条路必须走同一句，分家的那条早晚被漏掉。
            vm.endMigration()
            onDone()
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}
