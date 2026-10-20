import Foundation
import Testing
@testable import LedgerCore

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return c
}()

private func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

private func item(_ name: String, due: Date, cycle: Int = 12, price: Double = 0,
                  currency: Currency = .cny, auto: Bool = false) -> RenewalSnapshot {
    RenewalSnapshot(name: name, platform: "阿里云", dueDate: due, cycleMonths: cycle,
                    price: price, currency: currency, autoRenew: auto)
}

@Suite struct DateMathTests {
    @Test func advancingClampsToMonthEnd() {
        #expect(Calendar.iso(cal.advancing(day(2027, 1, 31), byMonths: 1), calendar: cal) == "2027-02-28")
        #expect(Calendar.iso(cal.advancing(day(2028, 1, 31), byMonths: 1), calendar: cal) == "2028-02-29")
        #expect(Calendar.iso(cal.advancing(day(2026, 10, 20), byMonths: 36), calendar: cal) == "2029-10-20")
    }

    @Test func daysIgnoreTimeOfDay() {
        #expect(cal.days(from: day(2026, 10, 20, 23), to: day(2026, 10, 21, 1)) == 1)
        #expect(cal.days(from: day(2026, 10, 20, 9), to: day(2026, 10, 15)) == -5)
    }
}

@Suite struct StatusTests {
    let today = day(2026, 10, 20, 10)

    @Test func boundaries() {
        func s(_ d: Date) -> RenewalStatus { .of(dueDate: d, today: today, reminderDays: 30, calendar: cal) }
        #expect(s(day(2026, 10, 15)) == .expired(days: 5))
        #expect(s(day(2026, 10, 20)) == .dueToday)
        #expect(s(day(2026, 10, 27)) == .urgent(days: 7))
        #expect(s(day(2026, 10, 28)) == .soon(days: 8))
        #expect(s(day(2026, 11, 19)) == .soon(days: 30))
        #expect(s(day(2026, 11, 20)) == .ok(days: 31))
        #expect(s(day(2026, 10, 15)).label == "已过期 5 天")
    }

    @Test func annualized() {
        let rates = ExchangeRates(usd: 7)
        #expect(Money.annualizedCNY(item("a", due: today, cycle: 1, price: 25, currency: .usd), rates: rates) == 2100)
        #expect(Money.annualizedCNY(item("b", due: today, cycle: 36, price: 90), rates: rates) == 30)
    }

    @Test func moneyFormat() {
        #expect(Money.format(39) == "¥39")
        #expect(Money.format(10.44, .usd) == "$10.44")
        #expect(Money.format(1500) == "¥1,500")
    }
}

@Suite struct ReminderPlannerTests {
    @Test func offsetsFollowReminderWindow() {
        #expect(ReminderPlanner.offsets(reminderDays: 30) == [30, 7, 3, 1, 0])
        #expect(ReminderPlanner.offsets(reminderDays: 5) == [5, 3, 1, 0])
    }

    @Test func schedulesOnlyFutureSlotsAtChosenHour() {
        let now = day(2026, 10, 20, 10)
        let plan = ReminderPlanner.plan([item("a.com", due: day(2026, 10, 27))], now: now,
                                        reminderDays: 30, hour: 9, calendar: cal)
        // 30 天前已经过去；7 天前是今天 9 点，也已过去；剩下 3、1、0 天。
        #expect(plan.map(\.title) == ["a.com 3 天后到期", "a.com 1 天后到期", "a.com 今天到期"])
        #expect(plan.first?.fireDate == day(2026, 10, 24, 9))
    }

    @Test func expiredItemNagsAtNextSlot() {
        let now = day(2026, 10, 20, 10)
        let plan = ReminderPlanner.plan([item("old.cn", due: day(2026, 10, 15))], now: now,
                                        reminderDays: 30, hour: 9, calendar: cal)
        #expect(plan.count == 1)
        #expect(plan[0].fireDate == day(2026, 10, 21, 9))
        #expect(plan[0].title == "old.cn 已过期 6 天")
    }

    @Test func respectsLimit() {
        let now = day(2026, 10, 20, 10)
        let items = (0..<40).map { item("d\($0).com", due: day(2026, 12, 1 + $0 % 28)) }
        #expect(ReminderPlanner.plan(items, now: now, reminderDays: 30, hour: 9, calendar: cal).count == 60)
    }
}

@Suite struct DigestPlannerTests {
    @Test func sendsOncePerStage() {
        let a = item("a.com", due: day(2026, 10, 27))
        let b = item("b.com", due: day(2027, 3, 1))
        let first = DigestPlanner.plan([a, b], sentStages: [:], today: day(2026, 10, 20, 9),
                                       reminderDays: 30, calendar: cal)
        #expect(first.shouldSend)
        #expect(first.entries.map(\.item.name) == ["a.com"])

        // 同一天再检查：阶段没变，不再发。
        let again = DigestPlanner.plan([a, b], sentStages: first.updatedStages, today: day(2026, 10, 21, 9),
                                       reminderDays: 30, calendar: cal)
        #expect(!again.shouldSend)

        // 进入 3 天阶段，再发一次。
        let later = DigestPlanner.plan([a, b], sentStages: first.updatedStages, today: day(2026, 10, 24, 9),
                                       reminderDays: 30, calendar: cal)
        #expect(later.shouldSend)
    }

    @Test func renewalResetsStages() {
        var a = item("a.com", due: day(2026, 10, 27))
        let first = DigestPlanner.plan([a], sentStages: [:], today: day(2026, 10, 20), reminderDays: 30, calendar: cal)
        a.dueDate = day(2027, 10, 27)
        let after = DigestPlanner.plan([a], sentStages: first.updatedStages, today: day(2026, 10, 20), reminderDays: 30, calendar: cal)
        #expect(after.entries.isEmpty)
        #expect(after.updatedStages.isEmpty)
    }

    @Test func bodyMentionsItems() {
        let plan = DigestPlanner.plan([item("a.com", due: day(2026, 10, 15), price: 39)], sentStages: [:],
                                      today: day(2026, 10, 20), reminderDays: 30, calendar: cal)
        #expect(DigestPlanner.subject(for: plan) == "域名续费提醒：1 项已过期，共 1 项需要处理")
        let body = DigestPlanner.body(for: plan, rates: ExchangeRates(), calendar: cal)
        #expect(body.contains("★ a.com  已过期 5 天（2026-10-15）"))
        #expect(body.contains("合计约 ¥39"))
    }
}

@Suite struct ImportTests {
    @Test func parsesMixedSeparators() {
        let text = """
        Example.com,阿里云,2027-03-18,12,69,CNY
        my.dev，Cloudflare，2027/1/5
        tab.io\tNamecheap\t2027.02.01\t24\t49.98\tusd

        broken line
        bad.date,GoDaddy,2027-02-30
        """
        let r = ImportParser.parse(text, calendar: cal)
        #expect(r.rows.count == 3)
        #expect(r.rows[0].name == "example.com")
        #expect(r.rows[0].price == 69)
        #expect(r.rows[1].cycleMonths == 12)
        #expect(r.rows[1].currency == .cny)
        #expect(r.rows[2].cycleMonths == 24)
        #expect(r.rows[2].currency == .usd)
        #expect(r.badLines == [5, 6])
    }
}

@Suite struct MailTests {
    @Test func mimeEncodesChineseSubjectAndBody() {
        let msg = MIMEMessage.build(from: "me@gmail.com", to: ["me@gmail.com"], subject: "续费提醒",
                                    body: "你好", date: Date(timeIntervalSince1970: 0), messageID: "x")
        #expect(msg.contains("Subject: =?UTF-8?B?57ut6LS55o+Q6YaS?="))
        #expect(msg.contains("Message-ID: <x@gmail.com>"))
        #expect(msg.hasSuffix("\r\n\r\n5L2g5aW9"))
        #expect(!msg.contains("\n\n"))  // 所有换行都是 CRLF
    }

    @Test func recipientsSplit() {
        #expect(SMTPConfig.splitRecipients("a@x.com, b@y.com；c@z.com") == ["a@x.com", "b@y.com", "c@z.com"])
        #expect(SMTPConfig.splitRecipients("a@x.com;b@y.com") == ["a@x.com", "b@y.com"])
    }

    @Test func sessionRunsProtocol() async throws {
        let fake = FakeTransport(replies: [
            "220 smtp.example.com ESMTP",
            "250-smtp.example.com", "250-AUTH LOGIN PLAIN", "250 8BITMIME",
            "334 VXNlcm5hbWU6", "334 UGFzc3dvcmQ6", "235 2.7.0 Accepted",
            "250 OK", "250 OK", "354 Go ahead", "250 2.0.0 OK queued", "221 bye",
        ])
        let config = SMTPConfig(host: "smtp.example.com", username: "me@example.com", password: "pw",
                                recipients: ["me@example.com"])
        try await SMTPSession(transport: fake).send(config: config, message: "Subject: t\r\n\r\nhi")
        #expect(fake.written == [
            "EHLO localhost\r\n", "AUTH LOGIN\r\n", "bWVAZXhhbXBsZS5jb20=\r\n", "cHc=\r\n",
            "MAIL FROM:<me@example.com>\r\n", "RCPT TO:<me@example.com>\r\n", "DATA\r\n",
            "Subject: t\r\n\r\nhi\r\n.\r\n", "QUIT\r\n",
        ])
        #expect(fake.closed)
    }

    @Test func authFailureIsReported() async {
        let fake = FakeTransport(replies: ["220 hi", "250 hi", "334 u", "334 p", "535 5.7.8 Username and Password not accepted"])
        let config = SMTPConfig(host: "h", username: "u@x.com", password: "p", recipients: ["u@x.com"])
        await #expect(throws: SMTPError.unexpectedReply(step: "登录", code: 535, message: "5.7.8 Username and Password not accepted")) {
            try await SMTPSession(transport: fake).send(config: config, message: "x")
        }
        #expect(fake.closed)
    }
}

private final class FakeTransport: SMTPTransport, @unchecked Sendable {
    var replies: [String]
    var written: [String] = []
    var closed = false

    init(replies: [String]) { self.replies = replies }

    func open() async throws {}
    func write(_ text: String) async throws { written.append(text) }
    func readLine() async throws -> String {
        guard !replies.isEmpty else { throw SMTPError.connection("no more replies") }
        return replies.removeFirst()
    }
    func close() { closed = true }
}
