import LedgerCore
import SwiftData
import SwiftUI

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.callout.monospaced())
                        .frame(minHeight: 180)
                        .domainInput()
                } header: {
                    Text("每行一条")
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("格式：域名, 平台, 到期日, 周期(月), 价格, 币种。后三项可以省略，默认每年、人民币。可以直接从 Numbers 或 Excel 复制。")
                        Text("例：example.com, 阿里云, 2027-03-18, 12, 69, CNY")
                            .font(.caption.monospaced())
                        if let error {
                            Text(error).foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("批量导入")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入", action: importRows)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 420)
        #endif
    }

    private func importRows() {
        let result = ImportParser.parse(text)
        guard result.badLines.isEmpty else {
            let lines = result.badLines.map(String.init).joined(separator: "、")
            error = "第 \(lines) 行格式不对：至少需要域名、平台和到期日（例如 2027-03-18）。"
            return
        }
        for row in result.rows {
            let r = Renewal(name: row.name, platform: row.platform, dueDate: row.dueDate)
            r.cycleMonths = row.cycleMonths
            r.price = row.price
            r.currency = row.currency
            context.insert(r)
        }
        dismiss()
    }
}
