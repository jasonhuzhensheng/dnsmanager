#if DEBUG
import Foundation
import LedgerCore
import SwiftData

/// 调试用示例数据：用 `-seedSamples` 启动参数打开，CI 截图时用它填满界面。只在空库时写入。
enum SampleData {
    @MainActor
    static func insertIfEmpty(into context: ModelContext) {
        guard ((try? context.fetchCount(FetchDescriptor<Renewal>())) ?? 0) == 0 else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today) ?? today }

        let samples: [(String, RenewalKind, String, String, Int, Int, Double, Currency, Bool)] = [
            ("example-shop.cn", .domain, "阿里云", "阿里云", -5, 12, 39, .cny, false),
            ("example-blog.com", .domain, "Cloudflare", "Cloudflare", 7, 12, 10.44, .usd, true),
            ("example-blog.com", .dns, "Cloudflare", "", 14, 1, 25, .usd, true),
            ("example-app.io", .domain, "Namecheap", "Cloudflare", 23, 12, 49.98, .usd, false),
            ("*.example-shop.cn", .certificate, "阿里云", "", 81, 12, 1500, .cny, false),
            ("example-studio.net", .domain, "腾讯云", "DNSPod", 139, 12, 79, .cny, false),
            ("example-brand.com", .domain, "GoDaddy", "Cloudflare", 610, 36, 65.97, .usd, false),
        ]
        for s in samples {
            let r = Renewal(name: s.0, platform: s.2, dueDate: day(s.4))
            r.kind = s.1
            r.dnsProvider = s.3
            r.cycleMonths = s.5
            r.price = s.6
            r.currency = s.7
            r.autoRenew = s.8
            r.note = "示例数据"
            context.insert(r)
        }
        try? context.save()
    }
}
#endif
