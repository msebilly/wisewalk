import SwiftUI

/// 批量增加。§6.6：拨完一整串念珠一次加 108，或从实体计数器上誊抄。
struct BatchSheet: View {
    /// 108 是全清单里唯一有客观依据的数字：一串念珠即 108 颗。
    /// 其余各档是它的倍数与整数档，方便从实体计数器誊抄。
    static let stepChoices = [1, 10, 21, 49, 100, 108, 216, 500, 1000, 1080]

    @Binding var step: Int
    let onConfirm: () -> Void

    /// 「加」键上写的那句话。**屏幕说的和做的必须是同一件事**——
    /// 这是唯一一处告诉用户「这一下要加多少」的地方，按下去就进账本，没有第二次确认。
    nonisolated static func confirmText(_ step: Int) -> String { "加 \(step)" }

    /// 能不能按「加」。
    ///
    /// ⛔ **0 不许按。** 自定框空着时 `numericText` 给回 0，而
    /// `CounterViewModel.setBatchStep` 会 `max(1,)` 把 0 抬成 1——
    /// 于是键上写着「加 0」、实际加了 1。**方向是「多」，而闭着眼睛数数的人永远发现不了。**
    nonisolated static func canConfirm(_ step: Int) -> Bool { step >= 1 }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @FocusState private var 自定聚焦: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("一次加多少")
                    .font(.headline)
                    .foregroundStyle(theme.primaryText)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 10)], spacing: 10) {
                    ForEach(Self.stepChoices, id: \.self) { choice in
                        Button {
                            step = choice
                        } label: {
                            Text("\(choice)")
                                .font(.body.monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.bordered)
                        .tint(step == choice ? theme.accent : theme.secondaryText)
                    }
                }

                // ⛔ 这里从前是 `Stepper(value: $step, in: 1...100_000)`。
                // 上限写着十万，而拨完 3 串念珠要记 324，档位里没有这个数，
                // 从 108 调过去**要点 216 下**。一个到不了的上限就是在说谎。
                //
                // 键盘输入用 `numericText` 而不是 `TextField(value:format:)`：
                // 后者会把 0 字面填进框里，光标落在它前面就成了十倍（见那边的长注释）。
                HStack {
                    Text("自定")
                        .foregroundStyle(theme.primaryText)
                    Spacer()
                    TextField("0", text: $step.numericText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit())
                        .frame(maxWidth: 120)
                        // 旁边那个「自定」是独立的 `Text`，跟这个框毫无关联，
                        // 读屏软件念到这儿只有孤零零一个「0」（占位符当了名字）。
                        .accessibilityLabel("自定数量")
                        .focused($自定聚焦)
                        // ⛔ **点进来就清空，这一行拦的是「多记三千倍」。**
                        //
                        // 框里预填着当前档位（默认 108）。用户拨完 3 串念珠进来输 324，
                        // 光标落在 108 **前面** → `324108`。实测截图拍到过，
                        // 键上明明白白写着「加 324108」。
                        //
                        // 这与 `numericText` 文档注释里那次十倍事故是同一个形状，
                        // 而 `numericText` 只把 **0** 映射成空串，**治不了预填非 0 值这一种**。
                        //
                        // 点进「自定」的人，本来就是因为档位里没有他要的数，清空正合他意。
                        // 清空后不打字就按不动「加」（`canConfirm(0) == false`）——那也是对的。
                        .onChange(of: 自定聚焦) { _, 聚焦 in if 聚焦 { step = 0 } }
                }

                Spacer()

                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text(Self.confirmText(step))
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!Self.canConfirm(step))
            }
            .padding(20)
            .pageBackground()
            .navigationTitle("批量增加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
