import Foundation

/// 台账里一条记录的类型。
public enum RenewalKind: String, CaseIterable, Codable, Sendable, Identifiable {
    case domain, dns, certificate, hosting, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .domain: "域名注册"
        case .dns: "DNS 解析套餐"
        case .certificate: "SSL 证书"
        case .hosting: "CDN / 托管"
        case .other: "其他"
        }
    }
}

public enum Currency: String, CaseIterable, Codable, Sendable, Identifiable {
    case cny = "CNY", usd = "USD", eur = "EUR", hkd = "HKD"

    public var id: String { rawValue }

    public var symbol: String {
        switch self {
        case .cny: "¥"
        case .usd: "$"
        case .eur: "€"
        case .hkd: "HK$"
        }
    }
}

/// 手动设置的汇率（1 外币 = ? 人民币）。不联网取汇率，因为续费金额只需要量级准确。
public struct ExchangeRates: Sendable, Equatable {
    public var usd: Double
    public var eur: Double
    public var hkd: Double

    public init(usd: Double = 7.1, eur: Double = 7.7, hkd: Double = 0.91) {
        self.usd = usd
        self.eur = eur
        self.hkd = hkd
    }

    public func toCNY(_ amount: Double, from currency: Currency) -> Double {
        switch currency {
        case .cny: amount
        case .usd: amount * usd
        case .eur: amount * eur
        case .hkd: amount * hkd
        }
    }
}

public struct BillingCycle: Hashable, Sendable, Identifiable {
    public let months: Int
    public let title: String

    public var id: Int { months }

    public static let options: [BillingCycle] = [
        .init(months: 1, title: "每月"), .init(months: 3, title: "每季度"),
        .init(months: 6, title: "每半年"), .init(months: 12, title: "每年"),
        .init(months: 24, title: "每 2 年"), .init(months: 36, title: "每 3 年"),
        .init(months: 60, title: "每 5 年"), .init(months: 120, title: "每 10 年"),
    ]

    public static func title(months: Int) -> String {
        options.first { $0.months == months }?.title ?? "每 \(months) 个月"
    }
}

/// 与存储层无关的一条记录快照，App 的 SwiftData 模型转换成它再交给纯逻辑处理。
public struct RenewalSnapshot: Sendable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var kind: RenewalKind
    public var platform: String
    public var dueDate: Date
    public var cycleMonths: Int
    public var price: Double
    public var currency: Currency
    public var autoRenew: Bool

    public init(
        id: UUID = UUID(), name: String, kind: RenewalKind = .domain, platform: String,
        dueDate: Date, cycleMonths: Int = 12, price: Double = 0, currency: Currency = .cny,
        autoRenew: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.platform = platform
        self.dueDate = dueDate
        self.cycleMonths = cycleMonths
        self.price = price
        self.currency = currency
        self.autoRenew = autoRenew
    }
}

public enum Money {
    /// 整数金额不带小数，其余保留两位：¥39、$10.44、¥1,500。
    public static func format(_ amount: Double, _ currency: Currency = .cny) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        let isWhole = abs(amount.rounded() - amount) < 0.005
        formatter.minimumFractionDigits = isWhole ? 0 : 2
        formatter.maximumFractionDigits = isWhole ? 0 : 2
        let text = formatter.string(from: NSNumber(value: amount)) ?? String(format: "%.2f", amount)
        return currency.symbol + text
    }

    /// 按付费周期折算到一年的人民币金额。
    public static func annualizedCNY(_ item: RenewalSnapshot, rates: ExchangeRates) -> Double {
        let months = max(item.cycleMonths, 1)
        return rates.toCNY(item.price, from: item.currency) * 12 / Double(months)
    }
}
