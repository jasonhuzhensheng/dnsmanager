#if os(macOS)
import LedgerCore
import SwiftData
import SwiftUI

/// 菜单栏面板：最近要处理的条目和几个快捷操作。
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Renewal.dueDate) private var renewals: [Renewal]
    @AppStorage(PrefKey.reminderDays) private var reminderDays = 30
    @AppStorage(PrefKey.emailEnabled) private var emailEnabled = false

    var body: some View {
        let window = max(reminderDays, 60)
        let upcoming = Array(renewals.filter { status(of: $0).daysLeft <= window }.prefix(8))

        VStack(alignment: .leading, spacing: 10) {
            Text("近期续费").font(.headline)
            if upcoming.isEmpty {
                Text(renewals.isEmpty ? "还没有记录" : "\(window) 天内没有需要续费的条目")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(upcoming) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.name).font(.callout.monospaced().weight(.medium)).lineLimit(1)
                            Text(r.platform).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        StatusPill(status: status(of: r))
                    }
                }
            }
            Divider()
            if emailEnabled, !appState.email.lastResult.isEmpty {
                Text(appState.email.lastResult)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                Button("打开台账") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                if emailEnabled {
                    Button("立即检查邮件") { Task { await appState.email.checkAndSend(force: true) } }
                        .disabled(appState.email.isSending)
                }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .help("设置")
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("退出")
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func status(of r: Renewal) -> RenewalStatus {
        .of(dueDate: r.dueDate, today: .now, reminderDays: reminderDays)
    }
}

/// 菜单栏图标：有已过期或 7 天内到期的条目时，换成带数字的感叹号图标。
struct MenuBarLabel: View {
    @Query(sort: \Renewal.dueDate) private var renewals: [Renewal]
    @AppStorage(PrefKey.reminderDays) private var reminderDays = 30

    var body: some View {
        let count = renewals.filter {
            RenewalStatus.of(dueDate: $0.dueDate, today: .now, reminderDays: reminderDays).severity == .critical
        }.count
        if count > 0 {
            Label("\(count)", systemImage: "exclamationmark.circle.fill")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "globe")
        }
    }
}
#endif
