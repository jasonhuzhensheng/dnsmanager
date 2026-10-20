import Foundation
import LedgerCore
import SwiftData

/// 台账里的一条记录。
///
/// 要走 CloudKit 同步，所以每个属性都有默认值、没有唯一约束（CloudKit 不支持）。
/// 续费记录存成 JSON 字符串，避免为它单独建一张关系表。
@Model
final class Renewal {
    var uuid: UUID = UUID()
    var name: String = ""
    var kindRaw: String = RenewalKind.domain.rawValue
    var platform: String = ""
    var dnsProvider: String = ""
    var dueDate: Date = Date.now
    var cycleMonths: Int = 12
    var price: Double = 0
    var currencyRaw: String = Currency.cny.rawValue
    var autoRenew: Bool = false
    var note: String = ""
    var createdAt: Date = Date.now
    var historyJSON: String = "[]"

    init(name: String, platform: String, dueDate: Date) {
        self.name = name
        self.platform = platform
        self.dueDate = dueDate
    }

    var kind: RenewalKind {
        get { RenewalKind(rawValue: kindRaw) ?? .other }
        set { kindRaw = newValue.rawValue }
    }

    var currency: Currency {
        get { Currency(rawValue: currencyRaw) ?? .cny }
        set { currencyRaw = newValue.rawValue }
    }

    var snapshot: RenewalSnapshot {
        RenewalSnapshot(
            id: uuid, name: name, kind: kind, platform: platform, dueDate: dueDate,
            cycleMonths: cycleMonths, price: price, currency: currency, autoRenew: autoRenew
        )
    }

    var history: [RenewalRecord] {
        get { (try? JSONDecoder().decode([RenewalRecord].self, from: Data(historyJSON.utf8))) ?? [] }
        set { historyJSON = (try? String(decoding: JSONEncoder().encode(newValue), as: UTF8.self)) ?? "[]" }
    }

    /// 标记已续费：到期日顺延一个周期，并记一笔续费记录（最多保留 20 条）。
    func markRenewed(calendar: Calendar = .current) {
        let next = calendar.advancing(dueDate, byMonths: max(cycleMonths, 1))
        let record = RenewalRecord(renewedAt: .now, fromDue: dueDate, toDue: next, price: price, currencyRaw: currencyRaw)
        history = Array(([record] + history).prefix(20))
        dueDate = next
    }
}

struct RenewalRecord: Codable, Hashable {
    var renewedAt: Date
    var fromDue: Date
    var toDue: Date
    var price: Double
    var currencyRaw: String
}
