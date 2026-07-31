import SwiftUI

/// §6.6 定课管理。
struct ItemListView: View {
    /// 用户会以为归档 = 删除，得说清楚不是。
    /// `PracticeItem` 只归档不硬删——硬删会让流水变孤儿，
    /// 孤儿被 `$0.item?.id == itemID` 挡在所有按项查询之外，等于静默蒸发。
    static let archiveDisclaimer = "收起来的功课不再出现在今日，以往的记录一条不少，随时可以恢复。"

    let store: PracticeItemStore
    @Binding var path: NavigationPath

    @Environment(\.theme) private var theme
    @State private var active: [PracticeItem] = []
    @State private var archived: [PracticeItem] = []
    @State private var showTemplates = false
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                ForEach(active) { item in
                    Button { path.append(Route.itemEditor(item.id)) } label: {
                        row(item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        Button("收起") { archive(item) }.tint(theme.secondaryText)
                    }
                }
                .onMove { from, to in move(from: from, to: to) }
            } header: {
                Text("我的定课")
            } footer: {
                if active.isEmpty {
                    Text("随分随力，先立一样。")
                }
            }

            if !archived.isEmpty {
                Section {
                    ForEach(archived) { item in
                        HStack {
                            row(item)
                            Spacer()
                            Button("恢复") { unarchive(item) }
                                .buttonStyle(.bordered)
                                .font(.footnote)
                        }
                    }
                } header: {
                    Text("已收起")
                } footer: {
                    Text(Self.archiveDisclaimer)
                }
            }
        }
        .navigationTitle("定课")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 用系统的「编辑」而不是常驻编辑态：常驻编辑态下 List 里的
            // Button 行点不动，用户就没法点进去改一门定课了。
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("从模板新建") { showTemplates = true }
                    Button("自定义") { path.append(Route.itemEditor(nil)) }
                } label: {
                    Label("新建", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showTemplates) {
            TemplatePickerSheet(store: store) { reload() }
        }
        .task { reload() }
        .alert("出了点问题", isPresented: .constant(failure != nil)) {
            Button("知道了") { failure = nil }
        } message: { Text(failure ?? "") }
    }

    private func row(_ item: PracticeItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconName)
                .foregroundStyle(Color(hex: item.colorHex))
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .foregroundStyle(theme.primaryText)
                Text(subtitle(item))
                    .font(.caption)
                    .foregroundStyle(theme.tertiaryText)
            }
        }
        .contentShape(Rectangle())
    }

    private func subtitle(_ item: PracticeItem) -> String {
        let kind = switch item.measureType {
        case .count: "计数"
        case .duration: "计时"
        case .check: "打勾"
        }
        guard let goal = item.dailyGoal else { return "\(kind) · 不设目标" }
        let amount = item.measureType == .duration
            ? DurationFormat.spoken(goal)
            : "\(goal)\(item.unit.isEmpty ? "" : " \(item.unit)")"
        return "\(kind) · 每日 \(amount)"
    }

    private func reload() {
        do {
            active = try store.activeItems()
            archived = try store.archivedItems()
        } catch { failure = error.localizedDescription }
    }

    private func move(from: IndexSet, to: Int) {
        var list = active
        list.move(fromOffsets: from, toOffset: to)
        do { try store.reorder(list); reload() }
        catch { failure = error.localizedDescription }
    }

    private func archive(_ item: PracticeItem) {
        do { try store.archive(item); reload() }
        catch { failure = error.localizedDescription }
    }

    private func unarchive(_ item: PracticeItem) {
        do { try store.unarchive(item); reload() }
        catch { failure = error.localizedDescription }
    }
}

/// 模板选择。模板只带出名称与计量方式，不带经文（版权与体积），不带目标值。
struct TemplatePickerSheet: View {
    let store: PracticeItemStore
    let onDone: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            List(TemplateCatalog.all, id: \.key) { t in
                Button {
                    add(t)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: t.iconName)
                            .foregroundStyle(theme.accent)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t.name).foregroundStyle(theme.primaryText)
                            Text(kindText(t)).font(.caption).foregroundStyle(theme.tertiaryText)
                        }
                    }
                }
            }
            .navigationTitle("从模板新建")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
            .alert("出了点问题", isPresented: .constant(failure != nil)) {
                Button("知道了") { failure = nil }
            } message: { Text(failure ?? "") }
        }
    }

    private func kindText(_ t: PracticeTemplate) -> String {
        switch t.measureType {
        case .count: t.unit.isEmpty ? "计数" : "计数 · \(t.unit)"
        case .duration: "计时"
        case .check: "打勾"
        }
    }

    private func add(_ t: PracticeTemplate) {
        do {
            _ = try store.create(from: t)
            onDone()
            dismiss()
        } catch { failure = error.localizedDescription }
    }
}
