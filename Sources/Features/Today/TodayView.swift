import SwiftUI

/// §6.1 今日。**默认落地页**：打开就该看见今天要做什么、做了多少。
struct TodayView: View {
    @Bindable var vm: TodayViewModel
    let settings: AppSettings
    @Binding var path: NavigationPath
    /// 底部那条常驻状态说什么，由它决定。
    ///
    /// ⛔ **故意不给默认值。** 视图层接线在本仓库零测试覆盖（八次变异实测），
    /// 而这条线一旦漏接，屏幕会照常显示「数据保存在本机」——
    /// 与「一切正常」那一档一模一样，**看不出来，也测不出来**。
    /// 不给默认值，编译器就替这根线站了岗；这是本卷对付视图层空洞
    /// 唯一有效的办法（结构性，不是覆盖）。
    let syncStatus: LedgerSyncStatusMonitor

    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    @State private var failure: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                // 判据是 `isRestDay` 不是 `rows.isEmpty`：空态的文案是「还没有定课」，
                // 只有**应做集合**真的为空才算数。同步半到时 rows 可能是空的，
                // 但那天明明有课——见 `TodayViewModel.unresolvedItemIDs`。
                if vm.isRestDay {
                    emptyState
                } else {
                    ForEach(vm.rows) { row in
                        rowView(row)
                    }
                    // rows 空而 unresolved 非空时这里本来是一片空白，
                    // 用户会以为 App 坏了。说实话比留白强。
                    if !vm.unresolvedItemIDs.isEmpty {
                        Text("还有 \(vm.unresolvedItemIDs.count) 项正在同步，稍后再看")
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                    }
                }
                // 今天新立的课今天用不了——**这件事必须说出来**。
                // 他 17:02 立了打坐回来看不见，分不清是「明天才算」还是「没存上」，
                // 而后一种解释会让他再立一遍，于是有了两门重名的课。
                //
                // 放在 `isRestDay` 判断**之外**：眼下休息日不可能有「明天起算」的课
                //（空快照会走追加路径），但这句话哪天真该出现时不该因为分支放错而消失。
                if !vm.startingTomorrow.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("「\(vm.startingTomorrow.joined(separator: "、"))」从明天开始记")
                            .font(.subheadline)
                            .foregroundStyle(theme.primaryText)
                        Text("今天的清单已经定下了，中途新立的课不改今天的账。")
                            .font(.footnote)
                            .foregroundStyle(theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .bottom) { BackupStatusBar(status: syncStatus.status) }
        .navigationTitle("今日")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { path.append(Route.manualEntry) } label: {
                    Label("补记", systemImage: "square.and.pencil")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { path.append(Route.itemList) } label: {
                    Label("定课", systemImage: "list.bullet")
                }
            }
        }
        .task { reload() }
        // 熄屏一夜再回来，日期已经变了。不刷新的话会往昨天记。
        .onChange(of: scenePhase) { _, phase in if phase == .active { reload() } }
        .alert("出了点问题", isPresented: .constant(failure != nil)) {
            Button("知道了") { failure = nil }
        } message: {
            Text(failure ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(dateText)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            Text(summaryText)
                .font(.subheadline)
                .foregroundStyle(vm.isFulfilled ? theme.fulfilled : theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("还没有定课")
                .font(.headline)
                .foregroundStyle(theme.primaryText)
            Text("随分随力，先立一样。")
                .font(.subheadline)
                .foregroundStyle(theme.secondaryText)
            Button("立一门定课") { path.append(Route.itemList) }
                .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 24)
    }

    private func rowView(_ row: TodayRow) -> some View {
        Button {
            tapped(row)
        } label: {
            HStack(spacing: 14) {
                ProgressRing(progress: row.progress,
                             colorHex: row.state == .fulfilled ? theme.fulfilledHex : row.colorHex,
                             trackHex: theme.tertiaryTextHex,
                             isFulfilled: row.state == .fulfilled,
                             iconName: row.iconName)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(row.name)
                            .font(.body.weight(.medium))
                            .foregroundStyle(theme.primaryText)
                        if row.isArchived {
                            Text("已归档")
                                .font(.caption2)
                                .foregroundStyle(theme.tertiaryText)
                        }
                    }
                    Text(FulfillmentBadge.progressText(total: row.total, goal: row.goal,
                                                       unit: row.unit,
                                                       measureType: row.measureType,
                                                       rounds: row.roundCount))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(theme.secondaryText)
                }
                Spacer(minLength: 8)
                FulfillmentLabel(state: row.state)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        // 状态必须进无障碍标签：环是装饰性的，只有这里说出来 VoiceOver 才听得到圆满与否。
        .accessibilityLabel(Text([
            row.name,
            row.isArchived ? "已归档" : nil,
            FulfillmentBadge.progressText(total: row.total, goal: row.goal,
                                          unit: row.unit, measureType: row.measureType,
                                          rounds: row.roundCount),
            FulfillmentBadge.text(for: row.state)
        ].compactMap { $0 }.joined(separator: "，")))
        .accessibilityAddTraits(.isButton)
    }

    private func tapped(_ row: TodayRow) {
        if let route = Route.forRecording(measureType: row.measureType, itemID: row.itemID) {
            guard !row.isArchived else { return }
            path.append(route)
        } else {
            do {
                try vm.toggleCheckbox(itemID: row.itemID,
                                      dayStartHour: settings.dayStartHour)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func reload() {
        do { try vm.reload(dayStartHour: settings.dayStartHour) }
        catch { failure = error.localizedDescription }
    }

    private var dateText: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "M 月 d 日 EEEE"
        guard let d = DayKey.calendarDate(of: vm.dayKey) else { return "今日" }
        return f.string(from: d)
    }

    private var summaryText: String {
        // 三处判据都必须走**应做集合**，不能走 rows：
        // rows 只是应做集合里画得出来的那部分，同步窗口内两者分家。
        // 拿 rows 判会把「今日无课」和「还有 0 项」打到屏幕上——
        // 前者替用户抹掉一天欠账，后者自相矛盾到用户无从理解。
        if vm.isRestDay { return "今日无课" }
        if vm.isFulfilled { return "今日圆满" }
        let left = vm.rows.filter { $0.state != .fulfilled }.count
            + vm.unresolvedItemIDs.count
        return "还有 \(left) 项"
    }
}

/// §6.1 底部常驻备份状态。
///
/// **说什么由 `LedgerSyncStatus` 一处说了算**——第 3 卷之前这里写死
/// 「数据保存在本机」，注释里留着「接上真实同步状态后替换文案」。
/// 现在接上了，但接上的是**我们真正知道的那点事**，不是原稿要的
/// 「已备份 · 刚刚 / 有 2 条待上传」（§5.2 已定案：那三句一句都说不出口）。
///
/// 宁可现在说得保守，也不能让用户以为已经有备份了——
/// 这个 App 唯一不能违背的承诺就是「不弄丢你的功课」。
struct BackupStatusBar: View {
    let status: LedgerSyncStatus
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "iphone")
            Text(status.barText)
        }
        .font(.footnote)
        .foregroundStyle(theme.secondaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        // 图标是装饰，读屏软件念一遍「iphone」没有意义。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.barText)
    }
}
