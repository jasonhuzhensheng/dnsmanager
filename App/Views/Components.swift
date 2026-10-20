import LedgerCore
import SwiftUI

extension Severity {
    var color: Color {
        switch self {
        case .critical: .red
        case .warning: .orange
        case .normal: .green
        }
    }
}

struct StatusPill: View {
    let status: RenewalStatus

    var body: some View {
        Text(status.label)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .foregroundStyle(status.severity.color)
            .background(status.severity.color.opacity(0.14), in: Capsule())
    }
}

struct BorderedTag: View {
    let text: String
    var tint: Color = .secondary

    var body: some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .foregroundStyle(tint)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(tint.opacity(0.6), lineWidth: 0.5))
    }
}

struct RenewalRow: View {
    let renewal: Renewal
    let status: RenewalStatus

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(renewal.name)
                        .font(.body.monospaced().weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if renewal.autoRenew { BorderedTag(text: "自动续费", tint: .green) }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                StatusPill(status: status)
                Text(priceText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        var parts = [renewal.platform, renewal.kind.title, Calendar.iso(renewal.dueDate)]
        if !renewal.dnsProvider.isEmpty, renewal.dnsProvider != renewal.platform {
            parts.insert("DNS：\(renewal.dnsProvider)", at: 1)
        }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var priceText: String {
        let cycle = BillingCycle.title(months: renewal.cycleMonths)
        return renewal.price > 0 ? "\(Money.format(renewal.price, renewal.currency)) / \(cycle)" : cycle
    }
}

/// 常见的注册商和 DNS 服务商，录入时可以直接选。
enum Platforms {
    static let suggestions = [
        "阿里云", "腾讯云", "华为云", "西部数码", "Cloudflare", "GoDaddy", "Namecheap", "Porkbun",
        "Dynadot", "Spaceship", "Name.com", "Gandi", "AWS Route 53", "DNSPod",
    ]
}

extension View {
    /// 输入域名时关掉自动大写和纠错（只有 iOS 有这些修饰符）。
    @ViewBuilder
    func domainInput() -> some View {
        #if os(iOS)
        self.textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(.URL)
        #else
        self.autocorrectionDisabled()
        #endif
    }
}
