import Foundation
import LedgerCore
import os
import SwiftData

enum Store {
    static let cloudContainerID = "iCloud.com.jasonhu.dnsmanager"
    static let log = Logger(subsystem: "com.jasonhu.dnsmanager", category: "store")

    /// 优先用 iCloud（CloudKit 私有库）同步；签名里没有 iCloud 权限时退回到只存本机，
    /// 并在设置页提示，不让 App 启动失败。
    static func makeContainer() -> (container: ModelContainer, syncsWithICloud: Bool) {
        let schema = Schema([Renewal.self])
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .private(cloudContainerID))
            return (try ModelContainer(for: schema, configurations: config), true)
        } catch {
            log.error("iCloud store unavailable, falling back to local: \(error.localizedDescription, privacy: .public)")
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
