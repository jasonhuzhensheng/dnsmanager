import Foundation

public struct ImportRow: Sendable, Equatable {
    public var name: String
    public var platform: String
    public var dueDate: Date
    public var cycleMonths: Int
    public var price: Double
    public var currency: Currency
}

public struct ImportResult: Sendable, Equatable {
    public var rows: [ImportRow]
    /// 解析失败的行号（从 1 开始，空行不计入也不报错）。
    public var badLines: [Int]
}

/// 解析从表格粘贴的文本：`域名,平台,到期日,周期(月),价格,币种`，后三项可省略。
/// 分隔符接受英文逗号、中文逗号和制表符（直接从 Numbers / Excel 复制出来是制表符）。
public enum ImportParser {
    public static func parse(_ text: String, calendar: Calendar = .current) -> ImportResult {
        var rows: [ImportRow] = []
        var bad: [Int] = []
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            let f = line.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "," || $0 == "，" || $0 == "\t" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard f.count >= 3, !f[0].isEmpty, !f[1].isEmpty,
                  let due = parseDate(f[2], calendar: calendar) else {
                bad.append(index + 1)
                continue
            }
            let cycle = f.count > 3 ? Int(f[3]) ?? 12 : 12
            let price = f.count > 4 ? Double(f[4]) ?? 0 : 0
            let currency = f.count > 5 ? Currency(rawValue: f[5].uppercased()) ?? .cny : .cny
            rows.append(ImportRow(
                name: f[0].lowercased(), platform: f[1], dueDate: due,
                cycleMonths: cycle > 0 ? cycle : 12, price: price, currency: currency
            ))
        }
        return ImportResult(rows: rows, badLines: bad)
    }

    /// 接受 2027-03-18、2027/3/18、2027.03.18。
    public static func parseDate(_ s: String, calendar: Calendar = .current) -> Date? {
        let parts = s.split(whereSeparator: { $0 == "-" || $0 == "/" || $0 == "." }).compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 1900, (1...12).contains(parts[1]), (1...31).contains(parts[2]) else {
            return nil
        }
        let comps = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: comps),
              calendar.component(.day, from: date) == parts[2] else { return nil } // 拒绝 2 月 30 日这类
        return date
    }
}
