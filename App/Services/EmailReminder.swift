#if os(macOS)
import Foundation
import LedgerCore
import Observation
import os
import SwiftData

/// Mac 端的邮件提醒。App 常驻菜单栏，每 30 分钟看一次：
/// 过了设置的提醒时刻、且有条目进入新的提醒阶段，就发一封汇总邮件。
/// 发送失败不记录阶段，下一轮会重试。
@MainActor
@Observable
final class EmailReminder {
    private(set) var lastResult: String = UserDefaults.standard.string(forKey: PrefKey.emailLastResult) ?? ""
    private(set) var isSending = false

    private let container: ModelContainer
    private var loop: Task<Void, Never>?
    private let log = Logger(subsystem: "com.jasonhu.dnsmanager", category: "email")

    init(container: ModelContainer) {
        self.container = container
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkAndSend()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    /// `force` 用于菜单里的「立即检查」：不等提醒时刻，但仍然只发有新阶段的条目。
    func checkAndSend(force: Bool = false) async {
        guard Preferences.emailEnabled, !isSending else { return }
        let now = Date.now
        guard force || Calendar.current.component(.hour, from: now) >= Preferences.notifyHour else { return }

        let config = Preferences.smtpConfig
        guard config.isComplete else {
            record("邮件设置不完整，未发送")
            return
        }
        let items = Store.snapshots(in: container.mainContext)
        let plan = DigestPlanner.plan(
            items, sentStages: Preferences.sentStages, today: now, reminderDays: Preferences.reminderDays
        )
        guard plan.shouldSend else {
            // 没有新阶段，但仍然清理掉已删除或已续费条目的阶段记录。
            Preferences.sentStages = plan.updatedStages
            if force { record("没有新的到期提醒需要发送") }
            return
        }

        isSending = true
        defer { isSending = false }
        do {
            try await Mailer.send(
                config: config,
                subject: DigestPlanner.subject(for: plan),
                body: DigestPlanner.body(for: plan, rates: Preferences.rates)
            )
            Preferences.sentStages = plan.updatedStages
            record("已发送提醒邮件（\(plan.entries.count) 项）")
        } catch {
            log.error("send failed: \(error.localizedDescription, privacy: .public)")
            record("发送失败：\(error.localizedDescription)")
        }
    }

    func sendTest() async {
        let config = Preferences.smtpConfig
        guard config.isComplete else {
            record("请先填写服务器、账号、密码和收件人")
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            try await Mailer.send(
                config: config,
                subject: "DNS Manager 测试邮件",
                body: "收到这封邮件说明 SMTP 设置正确。之后有域名进入提醒期时，会在每天 \(Preferences.notifyHour) 点后发汇总邮件。"
            )
            record("测试邮件已发送到 \(config.recipients.joined(separator: ", "))")
        } catch {
            record("发送失败：\(error.localizedDescription)")
        }
    }

    private func record(_ message: String) {
        let stamp = Date.now.formatted(date: .abbreviated, time: .shortened)
        lastResult = "\(stamp)  \(message)"
        UserDefaults.standard.set(lastResult, forKey: PrefKey.emailLastResult)
    }
}
#endif
