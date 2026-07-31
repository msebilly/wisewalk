import SwiftUI

struct ItemEditorView: View {
    /// spec §6.6 点名要求这句话**须在 UI 上明示**：
    /// 否则用户会担心「改了目标以前的记录是不是就废了」，
    /// 进而不敢调整定课量——那正好与「随分随力」背道而驰。
    static let goalDisclaimer = "改目标只影响今后。以前哪天圆满过，就一直是圆满的。"

    @Bindable var vm: ItemEditorViewModel

    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var goalText: String = ""
    @State private var failure: String?

    var body: some View {
        Form {
            Section("名称") {
                TextField("如：大悲咒", text: $vm.name)
            }

            Section("怎么记") {
                Picker("计量", selection: $vm.measureType) {
                    Text("计数").tag(MeasureType.count)
                    Text("计时").tag(MeasureType.duration)
                    Text("打勾").tag(MeasureType.check)
                }
                .pickerStyle(.segmented)
                // 记过功课就不许再改量法（`PracticeItemStore.update` 会掷
                // `.measureTypeLockedByHistory`）。这里必须**先禁用再解释**，
                // 不能让用户改完点保存才撞一个看不懂的错。
                .disabled(vm.isMeasureTypeLocked)

                if vm.isMeasureTypeLocked {
                    Text("已经记过功课，计量方式不能再改。要换记法请新建一项，这一项归档即可——过去的记录会照原样保留。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if vm.measureType == .count {
                    TextField("量词，如：遍 / 声 / 拜", text: $vm.unit)
                }
            }

            Section {
                ForEach(vm.goalChips, id: \.self) { chip in
                    Button {
                        vm.goalDisplay = chip
                        goalText = chip.map(String.init) ?? ""
                    } label: {
                        HStack {
                            Text(chip.map { goalLabel($0) } ?? "不设目标")
                                .foregroundStyle(theme.primaryText)
                            Spacer()
                            if vm.goalDisplay == chip {
                                Image(systemName: "checkmark").foregroundStyle(theme.accent)
                            }
                        }
                    }
                }
                HStack {
                    Text("自定")
                    Spacer()
                    TextField("不设目标", text: $goalText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit())
                        .frame(maxWidth: 120)
                        .onChange(of: goalText) { _, t in vm.goalDisplay = Int(t) }
                }
            } header: {
                Text(vm.measureType == .duration ? "每日目标（分钟）" : "每日目标")
            } footer: {
                Text(Self.goalDisclaimer)
            }

            Section("图标") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
                    ForEach(TemplateCatalog.iconChoices, id: \.self) { icon in
                        Button { vm.iconName = icon } label: {
                            Image(systemName: icon)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .foregroundStyle(vm.iconName == icon ? Color(hex: vm.colorHex) : theme.secondaryText)
                                .background(
                                    Circle().fill(vm.iconName == icon
                                                  ? Color(hex: vm.colorHex).opacity(0.15)
                                                  : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("颜色") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 48))], spacing: 12) {
                    ForEach(TemplateCatalog.colorChoices, id: \.self) { hex in
                        Button { vm.colorHex = hex } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                .overlay(
                                    Circle().strokeBorder(theme.primaryText,
                                                          lineWidth: vm.colorHex == hex ? 2 : 0)
                                )
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(hex)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle(vm.isEditing ? "改定课" : "立定课")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("存") { save() }.disabled(!vm.canSave)
            }
        }
        .task { goalText = vm.goalDisplay.map(String.init) ?? "" }
        // 计量方式一变，分钟与遍数的口径就不同了，输入框得跟着换算。
        .onChange(of: vm.measureType) { _, _ in
            goalText = vm.goalDisplay.map(String.init) ?? ""
        }
        .alert("出了点问题", isPresented: .constant(failure != nil)) {
            Button("知道了") { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private func goalLabel(_ v: Int) -> String {
        vm.measureType == .duration ? "\(v) 分" : "\(v)"
    }

    private func save() {
        do {
            try vm.save()
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}
