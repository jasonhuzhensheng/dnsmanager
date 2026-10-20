import Foundation
import LedgerCore
import UserNotifications

/// 把 ReminderPlanner 的排期写进系统通知中心。
/// 本 App 只有这一类通知，所以每次都整体清空再重排，不用比对差异。
@MainActor
enum NotificationScheduler {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func reschedule(_ items: [RenewalSnapshot]) async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        center.removeAllPendingNotificationRequests()
        let plan = ReminderPlanner.plan(
            items, now: .now, reminderDays: Preferences.reminderDays, hour: Preferences.notifyHour
        )
        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let request = UNNotificationRequest(
                identifier: reminder.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            )
            try? await center.add(request)
        }
        await updateBadge(items)
    }

    /// 图标角标显示需要处理的条目数（已过期 + 提醒期内）。
    static func updateBadge(_ items: [RenewalSnapshot]) async {
        let days = Preferences.reminderDays
        let count = items.filter {
            RenewalStatus.of(dueDate: $0.dueDate, today: .now, reminderDays: days).needsAttention
        }.count
        try? await UNUserNotificationCenter.current().setBadgeCount(count)
    }
}

/// App 在前台时也显示通知横幅（Mac 上常驻菜单栏，否则永远看不到通知）。
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
