import LedgerCore
import SwiftData
import SwiftUI

struct RenewalEditor: View {
    let renewal: Renewal?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name: String
    @State private var kind: RenewalKind
    @State private var platform: String
    @State private var dnsProvider: String
    @State private var dueDate: Date
    @State private var cycleMonths: Int
    @State private var price: Double
    @State private var currency: Currency
    @State private var autoRenew: Bool
    @State private var note: String
    @State private var confirmingDelete = false

    init(renewal: Renewal?) {
        self.renewal = renewal
        let nextYear = Calendar.current.advancing(Calendar.current.startOfDay(for: .now), byMonths: 12)
        _name = State(initialValue: renewal?.name ?? "")
        _kind = State(initialValue: renewal?.kind ?? .domain)
        _platform = State(initialValue: renewal?.platform ?? "")
        _dnsProvider = State(initialValue: renewal?.dnsProvider ?? "")
        _dueDate = State(initialValue: renewal?.dueDate ?? nextYear)
        _cycleMonths = State(initialValue: renewal?.cycleMonths ?? 12)
        _price = State(initialValue: renewal?.price ?? 0)
        _currency = State(initialValue: renewal?.currency ?? .cny)
        _autoRenew = State(initialValue: renewal?.autoRenew ?? false)
        _note = State(initialValue: renewal?.note ?? "")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces).lowercased() }
    private var trimmedPlatform: String { platform.trimmingCharacters(in: .whitespaces) }
    private var canSave: Bool { !trimmedName.isEmpty && !trimmedPlatform.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("域名 / 名称", text: $name, prompt: Text("example.com"))
                        .domainInput()
                    Picker("类型", selection: $kind) {
                        ForEach(RenewalKind.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("平台") {
                    platformField("付费平台", text: $platform, prompt: "阿里云")
                    platformField("DNS 解析商", text: $dnsProvider, prompt: "Cloudflare（可不填）")
                }
                Section("付费") {
                    DatePicker("下次到期日", selection: $dueDate, displayedComponents: .date)
                    Picker("付费周期", selection: $cycleMonths) {
                        ForEach(BillingCycle.options) { Text($0.title).tag($0.months) }
                    }
                    HStack {
                        TextField("续费价格", value: $price, format: .number)
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                        Picker("币种", selection: $currency) {
                            ForEach(Currency.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Toggle("已开启自动续费", isOn: $autoRenew)
                }
                Section("备注") {
                    TextField("账号、用途、绑定的卡……", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }
                if let renewal {
                    if !renewal.history.isEmpty {
                        Section("续费记录") {
                            ForEach(renewal.history, id: \.self) { h in
                                HStack {
                                    Text(h.renewedAt.formatted(date: .abbreviated, time: .omitted))
                                    Spacer()
                                    Text("\(Calendar.iso(h.fromDue)) → \(Calendar.iso(h.toDue))")
                                        .font(.callout.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    Section {
                        Button("已续费（到期日顺延一个周期）") {
                            renewal.markRenewed()
                            dismiss()
                        }
                        Button("删除", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(renewal == nil ? "添加条目" : "编辑条目")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).disabled(!canSave)
                }
            }
            .confirmationDialog("删除 \(renewal?.name ?? "")？", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("删除", role: .destructive) {
                    if let renewal { context.delete(renewal) }
                    dismiss()
                }
            } message: {
                Text("删除后无法恢复。")
            }
        }
        #if os(macOS)
        .frame(minWidth: 460, minHeight: 560)
        #endif
    }

    private func platformField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        HStack {
            TextField(title, text: text, prompt: Text(prompt))
            Menu {
                ForEach(Platforms.suggestions, id: \.self) { p in
                    Button(p) { text.wrappedValue = p }
                }
            } label: {
                Image(systemName: "chevron.down.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel("选择常用平台")
        }
    }

    private func save() {
        let target = renewal ?? Renewal(name: trimmedName, platform: trimmedPlatform, dueDate: dueDate)
        target.name = trimmedName
        target.kind = kind
        target.platform = trimmedPlatform
        target.dnsProvider = dnsProvider.trimmingCharacters(in: .whitespaces)
        target.dueDate = Calendar.current.startOfDay(for: dueDate)
        target.cycleMonths = cycleMonths
        target.price = max(price, 0)
        target.currency = currency
        target.autoRenew = autoRenew
        target.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if renewal == nil { context.insert(target) }
        dismiss()
    }
}
