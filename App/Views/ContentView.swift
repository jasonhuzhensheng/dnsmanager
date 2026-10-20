import LedgerCore
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Renewal.dueDate) private var renewals: [Renewal]

    @AppStorage(PrefKey.reminderDays) private var reminderDays = 30
    @AppStorage(PrefKey.notifyHour) private var notifyHour = 9
    @AppStorage(PrefKey.rateUSD) private var rateUSD = 7.1
    @AppStorage(PrefKey.rateEUR) private var rateEUR = 7.7
    @AppStorage(PrefKey.rateHKD) private var rateHKD = 0.91

    @State private var search = ""
    @State private var filter: Filter = .all
    @State private var editing: Renewal?
    @State private var showingNew = false
    @State private var showingImport = false
    @State private var showingSettings = false
    @State private var pendingDelete: Renewal?

    enum Filter: String, CaseIterable, Identifiable {
        case all = "全部", attention = "需处理", manual = "手动续费"
        var id: String { rawValue }
    }

    private var rates: ExchangeRates { ExchangeRates(usd: rateUSD, eur: rateEUR, hkd: rateHKD) }

    private func status(_ r: Renewal) -> RenewalStatus {
        .of(dueDate: r.dueDate, today: .now, reminderDays: reminderDays)
    }

    private var visible: [Renewal] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        return renewals.filter { r in
            switch filter {
            case .all: break
            case .attention: if !status(r).needsAttention { return false }
            case .manual: if r.autoRenew { return false }
            }
            guard !q.isEmpty else { return true }
            return [r.name, r.platform, r.dnsProvider, r.note, r.kind.title]
                .joined(separator: " ").lowercased().contains(q)
        }
    }

    /// 只有影响提醒的字段变了才重排通知。
    private var scheduleSignature: String {
        renewals.map { "\($0.uuid)|\($0.name)|\($0.dueDate.timeIntervalSince1970)|\($0.autoRenew)|\($0.price)" }
            .joined(separator: ",") + "|\(reminderDays)|\(notifyHour)"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryView(renewals: renewals.map(\.snapshot), reminderDays: reminderDays, rates: rates)
                }
                if renewals.isEmpty {
                    emptyState
                } else {
                    Section {
                        Picker("筛选", selection: $filter) {
                            ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    let items = visible
                    let attention = items.filter { status($0).needsAttention }
                    let rest = items.filter { !status($0).needsAttention }
                    if !attention.isEmpty {
                        Section("需要处理") { rows(attention) }
                    }
                    if !rest.isEmpty {
                        Section("之后到期") { rows(rest) }
                    }
                    if items.isEmpty {
                        Text("没有符合条件的条目").foregroundStyle(.secondary)
                    }
                    Section("各平台年化支出") {
                        PlatformBreakdown(renewals: renewals.map(\.snapshot), rates: rates)
                    }
                }
            }
            .navigationTitle("域名续费台账")
            .searchable(text: $search, prompt: "搜索域名、平台、备注")
            .toolbar { toolbar }
            .sheet(isPresented: $showingNew) { RenewalEditor(renewal: nil) }
            .sheet(item: $editing) { RenewalEditor(renewal: $0) }
            .sheet(isPresented: $showingImport) { ImportView() }
            #if os(iOS)
            .sheet(isPresented: $showingSettings) {
                NavigationStack { SettingsView() }
            }
            #endif
            .confirmationDialog(
                "删除 \(pendingDelete?.name ?? "")？",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) {
                    if let r = pendingDelete { context.delete(r) }
                    pendingDelete = nil
                }
            } message: {
                Text("删除后无法恢复，iCloud 上的副本也会一起删除。")
            }
            .task(id: scheduleSignature) {
                await NotificationScheduler.reschedule(renewals.map(\.snapshot))
            }
        }
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 520)
        #endif
    }

    @ViewBuilder
    private func rows(_ items: [Renewal]) -> some View {
        ForEach(items) { r in
            Button { editing = r } label: {
                RenewalRow(renewal: r, status: status(r))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .leading) {
                Button { r.markRenewed() } label: { Label("已续费", systemImage: "checkmark.circle") }
                    .tint(.green)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { pendingDelete = r } label: { Label("删除", systemImage: "trash") }
            }
            .contextMenu {
                Button { r.markRenewed() } label: { Label("已续费（顺延一个周期）", systemImage: "checkmark.circle") }
                Button { editing = r } label: { Label("编辑", systemImage: "pencil") }
                Divider()
                Button(role: .destructive) { pendingDelete = r } label: { Label("删除", systemImage: "trash") }
            }
        }
    }

    private var emptyState: some View {
        Section {
            VStack(spacing: 10) {
                Image(systemName: "globe")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("还没有记录").font(.headline)
                Text("点「添加」录入第一个域名，或用「批量导入」从表格粘贴。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                HStack {
                    Button("添加") { showingNew = true }.buttonStyle(.borderedProminent)
                    Button("批量导入") { showingImport = true }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button { showingNew = true } label: { Label("添加", systemImage: "plus") }
                .keyboardShortcut("n")
        }
        ToolbarItem(placement: .secondaryAction) {
            Button { showingImport = true } label: { Label("批量导入", systemImage: "square.and.arrow.down") }
        }
        #if os(iOS)
        ToolbarItem(placement: .topBarLeading) {
            Button { showingSettings = true } label: { Label("设置", systemImage: "gearshape") }
        }
        #endif
    }
}

struct SummaryView: View {
    let renewals: [RenewalSnapshot]
    let reminderDays: Int
    let rates: ExchangeRates

    var body: some View {
        let statuses = renewals.map { RenewalStatus.of(dueDate: $0.dueDate, today: .now, reminderDays: reminderDays) }
        let expired = statuses.filter { $0.daysLeft < 0 }.count
        let soon = statuses.filter { $0.daysLeft >= 0 && $0.daysLeft <= reminderDays }.count
        let annual = renewals.reduce(0) { $0 + Money.annualizedCNY($1, rates: rates) }
        let platforms = Set(renewals.map(\.platform)).count

        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
            stat("\(expired)", "已过期", expired > 0 ? .red : .primary)
            stat("\(soon)", "\(reminderDays) 天内到期", soon > 0 ? .orange : .primary)
            stat("\(renewals.count)", "在管条目 · \(platforms) 个平台", .primary)
            stat(Money.format(annual.rounded()), "年化支出（折合人民币）", .primary)
        }
        .padding(.vertical, 4)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct PlatformBreakdown: View {
    let renewals: [RenewalSnapshot]
    let rates: ExchangeRates

    private struct PlatformTotal {
        var name: String
        var count: Int
        var annual: Double
    }

    var body: some View {
        let groups = Dictionary(grouping: renewals) { $0.platform.isEmpty ? "未填平台" : $0.platform }
            .map { key, items in
                PlatformTotal(name: key, count: items.count, annual: items.reduce(0) { $0 + Money.annualizedCNY($1, rates: rates) })
            }
            .sorted { $0.annual > $1.annual }
        let maxValue = max(groups.map(\.annual).max() ?? 1, 1)

        ForEach(groups, id: \.name) { g in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(g.name)
                    Spacer()
                    Text("\(Money.format(g.annual.rounded())) · \(g.count) 项")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                GeometryReader { geo in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(4, geo.size.width * g.annual / maxValue))
                }
                .frame(height: 6)
            }
        }
    }
}
