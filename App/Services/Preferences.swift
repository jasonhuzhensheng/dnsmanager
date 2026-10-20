import Foundation
import LedgerCore

/// 设置项。每台设备各存一份（UserDefaults），不走 iCloud：
/// 提醒时间和邮件配置本来就是按设备定的，汇率两边各设一次即可。
enum PrefKey {
    static let reminderDays = "reminderDays"
    static let notifyHour = "notifyHour"
    static let rateUSD = "rateUSD"
    static let rateEUR = "rateEUR"
    static let rateHKD = "rateHKD"
    static let emailEnabled = "emailEnabled"
    static let smtpHost = "smtpHost"
    static let smtpPort = "smtpPort"
    static let smtpUser = "smtpUser"
    static let emailTo = "emailTo"
    static let emailSentStages = "emailSentStages"
    static let emailLastResult = "emailLastResult"
}

enum Preferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.reminderDays: 30,
            PrefKey.notifyHour: 9,
            PrefKey.rateUSD: 7.1,
            PrefKey.rateEUR: 7.7,
            PrefKey.rateHKD: 0.91,
            PrefKey.emailEnabled: false,
            PrefKey.smtpHost: "smtp.gmail.com",
            PrefKey.smtpPort: 465,
        ])
    }

    private static var d: UserDefaults { .standard }

    static var reminderDays: Int { min(max(d.integer(forKey: PrefKey.reminderDays), 1), 365) }
    static var notifyHour: Int { min(max(d.integer(forKey: PrefKey.notifyHour), 0), 23) }

    static var rates: ExchangeRates {
        ExchangeRates(
            usd: d.double(forKey: PrefKey.rateUSD),
            eur: d.double(forKey: PrefKey.rateEUR),
            hkd: d.double(forKey: PrefKey.rateHKD)
        )
    }

    static var emailEnabled: Bool { d.bool(forKey: PrefKey.emailEnabled) }

    static var smtpConfig: SMTPConfig {
        let user = (d.string(forKey: PrefKey.smtpUser) ?? "").trimmingCharacters(in: .whitespaces)
        let to = d.string(forKey: PrefKey.emailTo) ?? ""
        return SMTPConfig(
            host: (d.string(forKey: PrefKey.smtpHost) ?? "").trimmingCharacters(in: .whitespaces),
            port: d.integer(forKey: PrefKey.smtpPort),
            username: user,
            password: Keychain.smtpPassword(for: user) ?? "",
            recipients: SMTPConfig.splitRecipients(to.trimmingCharacters(in: .whitespaces).isEmpty ? user : to)
        )
    }

    static var sentStages: [String: Int] {
        get { d.dictionary(forKey: PrefKey.emailSentStages) as? [String: Int] ?? [:] }
        set { d.set(newValue, forKey: PrefKey.emailSentStages) }
    }
}
