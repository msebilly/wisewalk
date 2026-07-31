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

    private var isDuration: Bool { vm.selectedItem?.measureType == .duration }
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
        .alert("出了点问题", isPresented: .constant(failure != nil)) {
            Button("知道了") { failure = nil }
        } message: { Text(failure ?? "") }
        .alert("记上了", isPresented: .constant(toast != nil)) {
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
                    TextField("0", value: $vm.amount, format: .number)
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
                        TextField("0", value: $vm.amount, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospacedDigit())
                            .frame(maxWidth: 140)
                    }
                } footer: {
                    Text("会记成一笔单独的账，注明是以往累计，不会与日后的功课混在一起。只需做一次。")
                }
            }
            .navigationTitle("记入以往的累计")
            .navigationBarTitleDisplayMode(.inline)
            // ⛔ 这张表和补记表单共用同一个 `vm.amount`，所以两头都得自己擦干净。
            // 不擦的话：在这儿敲了 290000，想想不对又按「取消」，退回补记页——
            // 数量框里就是 290000，再顺手一点「记上」，**今天凭空多出 29 万声**。
            // 这是全卷方向最坏、量级最大的一处「多」，而它只是因为两张表共用一个数。
            .onAppear { vm.amount = 0 }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { vm.amount = 0; dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("记上") { submit() }
                        .disabled(!vm.canSubmit())
                }
            }
            .alert("出了点问题", isPresented: .constant(failure != nil)) {
                Button("知道了") { failure = nil }
            } message: { Text(failure ?? "") }
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        do {
            _ = try vm.submitMigrationTotal()
            vm.amount = 0
            onDone()
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}
