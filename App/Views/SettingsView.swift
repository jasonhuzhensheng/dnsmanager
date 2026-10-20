import LedgerCore
import SwiftUI
import UserNotifications
#if os(macOS)
import ServiceManagement
#endif

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    #if os(iOS)
    @Environment(\.openURL) private var openURL
    #endif

    @AppStorage(PrefKey.reminderDays) private var reminderDays = 30
    @AppStorage(PrefKey.notifyHour) private var notifyHour = 9
    @AppStorage(PrefKey.rateUSD) private var rateUSD = 7.1
    @AppStorage(PrefKey.rateEUR) private var rateEUR = 7.7
    @AppStorage(PrefKey.rateHKD) private var rateHKD = 0.91

    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section {
                Stepper("到期前 \(reminderDays) 天开始提醒", value: $reminderDays, in: 1...180)
                Picker("每天提醒时间", selection: $notifyHour) {
                    ForEach(6..<23, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                HStack {
                    Text("系统通知")
                    Spacer()
                    notificationControl
                }
            } header: {
                Text("提醒")
            } footer: {
                Text("会在提醒期开始、到期前 7 天、3 天、1 天和当天各通知一次；过期后每天提醒。")
            }

            Section("汇率（1 外币 = ? 人民币）") {
                rateField("美元 USD", value: $rateUSD)
                rateField("欧元 EUR", value: $rateEUR)
                rateField("港币 HKD", value: $rateHKD)
            }

            Section("同步") {
                Label(
                    appState.syncsWithICloud ? "通过 iCloud 在 Mac 和 iPhone 之间同步" : "iCloud 同步未启用，数据只存在本机",
                    systemImage: appState.syncsWithICloud ? "icloud" : "icloud.slash"
                )
                .foregroundStyle(appState.syncsWithICloud ? Color.primary : Color.orange)
            }

            #if os(macOS)
            EmailSettingsSection()
            LaunchAtLoginSection()
            #endif
        }
        .formStyle(.grouped)
        .navigationTitle("设置")
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
        }
        #else
        .frame(minWidth: 480, minHeight: 560)
        #endif
        .task { notificationStatus = await NotificationScheduler.authorizationStatus() }
    }

    @ViewBuilder
    private var notificationControl: some View {
        if notificationStatus == .authorized || notificationStatus == .provisional {
            Text("已开启").foregroundStyle(.secondary)
        } else if notificationStatus == .notDetermined {
            Button("开启") {
                Task {
                    _ = await NotificationScheduler.requestAuthorization()
                    notificationStatus = await NotificationScheduler.authorizationStatus()
                }
            }
        } else {
            #if os(iOS)
            Button("去系统设置开启") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
            }
            #else
            Text("已关闭，请在「系统设置 › 通知」中开启").foregroundStyle(.orange)
            #endif
        }
    }

    private func rateField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 100)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }
}

#if os(macOS)
private struct EmailSettingsSection: View {
    @Environment(AppState.self) private var appState
    @AppStorage(PrefKey.emailEnabled) private var enabled = false
    @AppStorage(PrefKey.smtpHost) private var host = "smtp.gmail.com"
    @AppStorage(PrefKey.smtpPort) private var port = 465
    @AppStorage(PrefKey.smtpUser) private var user = ""
    @AppStorage(PrefKey.emailTo) private var to = ""
    @State private var password = ""
    @State private var passwordSaved = false

    var body: some View {
        Section {
            Toggle("每天检查并发送邮件提醒", isOn: $enabled)
            TextField("SMTP 服务器", text: $host)
            TextField("端口", value: $port, format: .number.grouping(.never))
            TextField("邮箱账号", text: $user, prompt: Text("you@gmail.com"))
                .autocorrectionDisabled()
            HStack {
                SecureField("应用专用密码", text: $password, prompt: Text(passwordSaved ? "已保存在钥匙串" : "16 位应用专用密码"))
                Button("保存") {
                    passwordSaved = Keychain.setSMTPPassword(password, for: user.trimmingCharacters(in: .whitespaces))
                    password = ""
                }
                .disabled(password.isEmpty || user.isEmpty)
            }
            TextField("收件人", text: $to, prompt: Text("留空则发给自己，多个用逗号分隔"))
                .autocorrectionDisabled()
            HStack {
                Button("发送测试邮件") { Task { await appState.email.sendTest() } }
                Button("立即检查") { Task { await appState.email.checkAndSend(force: true) } }
                    .disabled(!enabled)
                if appState.email.isSending { ProgressView().controlSize(.small) }
            }
            if !appState.email.lastResult.isEmpty {
                Text(appState.email.lastResult)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        } header: {
            Text("邮件提醒（仅 Mac）")
        } footer: {
            Text("App 在菜单栏常驻时生效，每天过了提醒时间后检查一次，有条目进入新的提醒阶段才发汇总邮件。Gmail 要先开启两步验证，再到 myaccount.google.com/apppasswords 生成应用专用密码；QQ / 163 邮箱用「授权码」。服务器都用 465 端口（SSL）。")
        }
        .onAppear { refreshSaved() }
        .onChange(of: user) { refreshSaved() }
    }

    private func refreshSaved() {
        passwordSaved = Keychain.smtpPassword(for: user.trimmingCharacters(in: .whitespaces)) != nil
    }
}

private struct LaunchAtLoginSection: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Section {
            Toggle("登录时自动启动", isOn: $enabled)
                .onChange(of: enabled) {
                    do {
                        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        error = nil
                    } catch let e {
                        error = e.localizedDescription
                        enabled = SMAppService.mainApp.status == .enabled
                    }
                }
            if let error { Text(error).foregroundStyle(.red).font(.callout) }
        } footer: {
            Text("开机后自动在菜单栏运行，邮件提醒才不会漏。")
        }
    }
}
#endif
