import Foundation
import LedgerCore
import os
import SwiftData

enum Store {
    static let cloudContainerID = "iCloud.com.jasonhu.dnsmanager"
    static let log = Logger(subsystem: "com.jasonhu.dnsmanager", category: "store")

    /// 构建设置 ENABLE_CLOUDKIT 写进 Info.plist 的 DNSMCloudKit。
    /// 没有 iCloud 权限（未签名的 CI 构建、免费开发者账号）时 CloudKit 会在后台线程直接中断进程，
    /// 不会抛错，所以只能在构建时关掉，而不是靠下面的 catch 兜底（2026-10-20 CI 模拟器实测）。
    static var cloudKitEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "DNSMCloudKit") as? String)?.uppercased() != "NO"
    }

    /// 优先用 iCloud（CloudKit 私有库）同步；关掉或初始化失败时只存本机，并在设置页提示。
    static func makeContainer() -> (container: ModelContainer, syncsWithICloud: Bool) {
        let schema = Schema([Renewal.self])
        if cloudKitEnabled {
            do {
                let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
                return (try ModelContainer(for: schema, configurations: config), true)
            } catch {
                log.error("iCloud store unavailable, falling back to local: \(error.localizedDescription, privacy: .public)")
            }
        }
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return (try ModelContainer(for: schema, configurations: config), false)
        } catch {
            fatalError("无法打开本地数据库：\(error)")
        }
    }

    @MainActor
    static func snapshots(in context: ModelContext) -> [RenewalSnapshot] {
        ((try? context.fetch(FetchDescriptor<Renewal>())) ?? []).map(\.snapshot)
    }
}
