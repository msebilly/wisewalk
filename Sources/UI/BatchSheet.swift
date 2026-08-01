import SwiftUI

/// 批量增加。§6.6：拨完一整串念珠一次加 108，或从实体计数器上誊抄。
struct BatchSheet: View {
    /// 108 是全清单里唯一有客观依据的数字：一串念珠即 108 颗。
    /// 其余各档是它的倍数与整数档，方便从实体计数器誊抄。
    static let stepChoices = [1, 10, 21, 49, 100, 108, 216, 500, 1000, 1080]

    @Binding var step: Int
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme

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

                Stepper(value: $step, in: 1...100_000) {
                    Text("自定：\(step)").font(.body.monospacedDigit())
                        .foregroundStyle(theme.primaryText)
                }

                Spacer()

                Button {
                    onConfirm()
                    dismiss()
                } label: {
                    Text("加 \(step)")
                        .font(.headline.monospacedDigit())
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
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
