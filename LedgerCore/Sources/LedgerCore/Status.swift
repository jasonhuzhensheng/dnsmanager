import Foundation

public extension Calendar {
    /// 两个日期相差的整天数（按本地日历的日界线算，不受具体时刻影响）。
    func days(from start: Date, to end: Date) -> Int {
        dateComponents([.day], from: startOfDay(for: start), to: startOfDay(for: end)).day ?? 0
    }

    /// 顺延若干个月。Foundation 会把月底对齐，1 月 31 日加一个月得到 2 月 28/29 日。
    func advancing(_ day: Date, byMonths months: Int) -> Date {
        date(byAdding: .month, value: months, to: day) ?? day
    }

    static func iso(_ day: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

public enum Severity: Sendable {
    case critical, warning, normal
}

public enum RenewalStatus: Equatable, Sendable {
    /// 已过期，`days` 为过期天数（≥1）。
    case expired(days: Int)
    case dueToday
    /// 1…7 天内到期。
    case urgent(days: Int)
    /// 在提醒期内（8…reminderDays 天）。
    case soon(days: Int)
    case ok(days: Int)

    public static func of(
        dueDate: Date, today: Date, reminderDays: Int, calendar: Calendar = .current
    ) -> RenewalStatus {
        let d = calendar.days(from: today, to: dueDate)
        if d < 0 { return .expired(days: -d) }
        if d == 0 { return .dueToday }
        if d <= 7 { return .urgent(days: d) }
        if d <= reminderDays { return .soon(days: d) }
        return .ok(days: d)
    }

    /// 距到期的天数，过期为负数。
    public var daysLeft: Int {
        switch self {
        case .expired(let d): -d
        case .dueToday: 0
        case .urgent(let d), .soon(let d), .ok(let d): d
        }
    }

    public var severity: Severity {
        switch self {
        case .expired, .dueToday, .urgent: .critical
        case .soon: .warning
        case .ok: .normal
        }
    }

    public var needsAttention: Bool { severity != .normal }

    public var label: String {
        switch self {
        case .expired(let d): "已过期 \(d) 天"
        case .dueToday: "今天到期"
        case .urgent(let d), .soon(let d): "\(d) 天后到期"
        case .ok(let d): "\(d) 天后"
        }
    }
}
