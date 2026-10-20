import Foundation

/// 一条要预先排进系统的本地通知。
public struct PlannedReminder: Sendable, Equatable {
    public var id: String
    public var fireDate: Date
    public var title: String
    public var body: String
}

/// 本地通知排期。通知是提前排好的，App 不在前台也会按时弹出；
/// 数据变化后整体重排一次（先清空再按这里的结果添加）。
public enum ReminderPlanner {
    /// iOS 每个 App 最多保留 64 条待发通知，留一点余量。
    public static let defaultLimit = 60

    /// 到期前第几天提醒：提醒期开始、7 天、3 天、1 天、当天。
    public static func offsets(reminderDays: Int) -> [Int] {
        Array(Set([reminderDays, 7, 3, 1, 0].filter { $0 >= 0 && $0 <= max(reminderDays, 0) } + [0]))
            .sorted(by: >)
    }

    public static func plan(
        _ items: [RenewalSnapshot], now: Date, reminderDays: Int, hour: Int,
        calendar: Calendar = .current, limit: Int = defaultLimit
    ) -> [PlannedReminder] {
        var result: [PlannedReminder] = []
        let todayAtHour = at(hour, on: now, calendar: calendar)
        // 已过期的条目：在下一个提醒时刻再催一次。每次打开 App 都会重排，所以过期期间每天都会提醒。
        let nextSlot = todayAtHour > now
            ? todayAtHour
            : at(hour, on: calendar.date(byAdding: .day, value: 1, to: now) ?? now, calendar: calendar)

        for item in items {
            let key = "\(item.id.uuidString)-\(Calendar.iso(item.dueDate, calendar: calendar))"
            let daysLeft = calendar.days(from: now, to: item.dueDate)
            if daysLeft < 0 {
                let overdue = calendar.days(from: nextSlot, to: item.dueDate)
                result.append(PlannedReminder(
                    id: "\(key)-overdue",
                    fireDate: nextSlot,
                    title: "\(item.name) 已过期 \(-overdue) 天",
                    body: body(for: item)
                ))
                continue
            }
            for offset in offsets(reminderDays: reminderDays) {
                guard let day = calendar.date(byAdding: .day, value: -offset, to: item.dueDate) else { continue }
                let fire = at(hour, on: day, calendar: calendar)
                guard fire > now else { continue }
                result.append(PlannedReminder(
                    id: "\(key)-\(offset)",
                    fireDate: fire,
                    title: offset == 0 ? "\(item.name) 今天到期" : "\(item.name) \(offset) 天后到期",
                    body: body(for: item)
                ))
            }
        }
        return Array(result.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    static func body(for item: RenewalSnapshot) -> String {
        var parts = [item.platform, item.kind.title]
        if item.price > 0 {
            parts.append("\(Money.format(item.price, item.currency)) / \(BillingCycle.title(months: item.cycleMonths))")
        }
        parts.append(item.autoRenew ? "已开自动续费，确认扣款卡有效" : "需要手动续费")
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    static func at(_ hour: Int, on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: 0, second: 0, of: calendar.startOfDay(for: day)) ?? day
    }
}

/// 邮件提醒的阶段。每条记录每进入一个更紧急的阶段就发一次，
/// Mac 睡眠错过几天也只补发一封，不会重复。
public enum EmailStage: Int, Comparable, Sendable {
    case none = 0, window, week, threeDays, tomorrow, today, expired

    public static func < (a: EmailStage, b: EmailStage) -> Bool { a.rawValue < b.rawValue }

    public static func of(daysLeft d: Int, reminderDays: Int) -> EmailStage {
        if d < 0 { return .expired }
        if d == 0 { return .today }
        if d <= 1 { return .tomorrow }
        if d <= 3 { return .threeDays }
        if d <= 7 { return .week }
        if d <= reminderDays { return .window }
        return .none
    }
}

public struct DigestEntry: Sendable, Equatable {
    public var item: RenewalSnapshot
    public var status: RenewalStatus
    public var isNew: Bool
}

public struct DigestPlan: Sendable, Equatable {
    /// 需要写进邮件的条目（所有进入提醒期的），按到期日排序。
    public var entries: [DigestEntry]
    /// 发送成功后要保存的阶段记录；已不在台账里的条目会被剔除。
    public var updatedStages: [String: Int]
    public var shouldSend: Bool { entries.contains { $0.isNew } }
}

public enum DigestPlanner {
    /// 阶段记录的键带上到期日：续费后到期日变了，就从头开始提醒。
    public static func key(for item: RenewalSnapshot, calendar: Calendar = .current) -> String {
        "\(item.id.uuidString)|\(Calendar.iso(item.dueDate, calendar: calendar))"
    }

    public static func plan(
        _ items: [RenewalSnapshot], sentStages: [String: Int], today: Date, reminderDays: Int,
        calendar: Calendar = .current
    ) -> DigestPlan {
        var entries: [DigestEntry] = []
        var updated: [String: Int] = [:]
        for item in items {
            let status = RenewalStatus.of(dueDate: item.dueDate, today: today, reminderDays: reminderDays, calendar: calendar)
            let stage = EmailStage.of(daysLeft: status.daysLeft, reminderDays: reminderDays)
            let k = key(for: item, calendar: calendar)
            let sent = sentStages[k] ?? 0
            guard stage != .none else { continue }
            entries.append(DigestEntry(item: item, status: status, isNew: stage.rawValue > sent))
            updated[k] = max(stage.rawValue, sent)
        }
        entries.sort { $0.item.dueDate < $1.item.dueDate }
        return DigestPlan(entries: entries, updatedStages: updated)
    }

    public static func subject(for plan: DigestPlan) -> String {
        let expired = plan.entries.filter { $0.status.daysLeft < 0 }.count
        if expired > 0 {
            return "域名续费提醒：\(expired) 项已过期，共 \(plan.entries.count) 项需要处理"
        }
        return "域名续费提醒：\(plan.entries.count) 项即将到期"
    }

    public static func body(for plan: DigestPlan, rates: ExchangeRates, calendar: Calendar = .current) -> String {
        var lines = ["以下条目已过期或即将到期（★ 为本次新进入提醒阶段的）：", ""]
        for e in plan.entries {
            let item = e.item
            var line = "\(e.isNew ? "★" : "・") \(item.name)  \(e.status.label)（\(Calendar.iso(item.dueDate, calendar: calendar))）"
            line += "\n    \(ReminderPlanner.body(for: item))"
            lines.append(line)
        }
        let total = plan.entries.reduce(0) { $0 + rates.toCNY($1.item.price, from: $1.item.currency) }
        if total > 0 {
            lines += ["", "合计约 \(Money.format(total))（按设置里的汇率折算）。"]
        }
        lines += ["", "—— 由 DNS Manager 在你的 Mac 上发送"]
        return lines.joined(separator: "\n")
    }
}
