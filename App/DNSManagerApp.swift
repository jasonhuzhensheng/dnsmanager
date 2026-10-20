import LedgerCore
import Observation
import SwiftData
import SwiftUI
import UserNotifications
#if os(iOS)
import BackgroundTasks
#endif

/// 全局状态：数据容器、是否在用 iCloud，以及 Mac 上的邮件提醒服务。
@MainActor
@Observable
final class AppState {
    let container: ModelContainer
    let syncsWithICloud: Bool
    #if os(macOS)
    let email: EmailReminder
    #endif

    init() {
        Preferences.registerDefaults()
        let (container, cloud) = Store.makeContainer()
        self.container = container
        self.syncsWithICloud = cloud
        #if os(macOS)
        email = EmailReminder(container: container)
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-seedSamples") {
            SampleData.insertIfEmpty(into: container.mainContext)
        }
        #endif
    }

    func rescheduleNotifications() async {
        await NotificationScheduler.reschedule(Store.snapshots(in: container.mainContext))
    }
}

@main
struct DNSManagerApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    static let refreshTaskID = "com.jasonhu.dnsmanager.refresh"

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(appState)
                .task {
                    // 第一次启动时请求通知权限；之后系统不会再弹窗，直接返回当前结果。
                    if await NotificationScheduler.authorizationStatus() == .notDetermined {
                        _ = await NotificationScheduler.requestAuthorization()
                    }
                    await appState.rescheduleNotifications()
                    #if os(macOS)
                    appState.email.start()
                    #endif
                }
        }
        .modelContainer(appState.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // 另一台设备改过的数据会经 iCloud 同步过来，回到前台时重排一次通知。
                Task { await appState.rescheduleNotifications() }
            case .background:
                #if os(iOS)
                Self.scheduleBackgroundRefresh()
                #endif
            default:
                break
            }
        }
        #if os(iOS)
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            // iPhone 没打开 App 时，Mac 上新加的条目也要排上通知：系统不定期唤醒 App 重排。
            Self.scheduleBackgroundRefresh()
            await appState.rescheduleNotifications()
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(appState)
                .modelContainer(appState.container)
        }

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .modelContainer(appState.container)
                .task { appState.email.start() }
        } label: {
            MenuBarLabel()
                .modelContainer(appState.container)
                .task {
                    // 菜单栏图标在 App 启动时就会创建，即使主窗口被关掉也能启动邮件检查。
                    appState.email.start()
                }
        }
        .menuBarExtraStyle(.window)
        #endif
    }

    #if os(iOS)
    nonisolated static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
        try? BGTaskScheduler.shared.submit(request)
    }
    #endif
}
