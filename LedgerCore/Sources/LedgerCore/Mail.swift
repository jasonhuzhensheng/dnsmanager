import Foundation

public struct SMTPConfig: Sendable, Equatable {
    public var host: String
    public var port: Int
    public var username: String
    public var password: String
    /// 收件人，可以用逗号分隔多个。
    public var recipients: [String]

    public init(host: String, port: Int = 465, username: String, password: String, recipients: [String]) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.recipients = recipients
    }

    public var isComplete: Bool {
        !host.isEmpty && port > 0 && !username.isEmpty && !password.isEmpty && !recipients.isEmpty
    }

    public static func splitRecipients(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == "," || $0 == "，" || $0 == ";" || $0 == "；" || $0 == " " })
            .map(String.init)
            .filter { $0.contains("@") }
    }
}

public enum SMTPError: Error, LocalizedError, Equatable {
    case connection(String)
    case unexpectedReply(step: String, code: Int, message: String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .connection(let m): "连接邮件服务器失败：\(m)"
        case .unexpectedReply(let step, let code, let message):
            code == 535 || code == 534
                ? "登录被拒绝（\(code)）。Gmail 需要使用「应用专用密码」，不是账号密码。\(message)"
                : "服务器在「\(step)」步骤返回 \(code)：\(message)"
        case .timeout: "连接邮件服务器超时"
        }
    }
}

/// 一问一答的行式传输。实际实现是 Network.framework 的 TLS 连接，测试里用假的。
public protocol SMTPTransport: AnyObject {
    func open() async throws
    func write(_ text: String) async throws
    func readLine() async throws -> String
    func close()
}

public enum MIMEMessage {
    /// 生成完整报文（CRLF 换行）。正文用 base64 编码，中文不会乱码，也不需要处理行首的点。
    public static func build(
        from: String, to: [String], subject: String, body: String,
        date: Date = .now, messageID: String = UUID().uuidString
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        let domain = from.split(separator: "@").last.map(String.init) ?? "localhost"
        let encodedBody = Data(body.utf8).base64EncodedString(options: [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed])
        let headers = [
            "From: \(encodeWord("DNS Manager")) <\(from)>",
            "To: \(to.joined(separator: ", "))",
            "Subject: \(encodeWord(subject))",
            "Date: \(formatter.string(from: date))",
            "Message-ID: <\(messageID)@\(domain)>",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8",
            "Content-Transfer-Encoding: base64",
        ]
        return headers.joined(separator: "\r\n") + "\r\n\r\n" + encodedBody
    }

    /// RFC 2047 编码的头部字段。
    static func encodeWord(_ s: String) -> String {
        "=?UTF-8?B?\(Data(s.utf8).base64EncodedString())?="
    }
}

/// 最小的 SMTP 客户端：只支持隐式 TLS（465 端口）+ AUTH LOGIN。
/// Gmail、QQ 邮箱、163、iCloud 邮件的 465 端口都是这种方式。
public final class SMTPSession {
    private let transport: SMTPTransport

    public init(transport: SMTPTransport) {
        self.transport = transport
    }

    public func send(config: SMTPConfig, message: String, heloName: String = "localhost") async throws {
        try await transport.open()
        defer { transport.close() }
        try await expect([220], step: "连接")
        try await command("EHLO \(heloName)", expect: [250], step: "EHLO")
        try await command("AUTH LOGIN", expect: [334], step: "登录")
        try await command(Data(config.username.utf8).base64EncodedString(), expect: [334], step: "登录")
        try await command(Data(config.password.utf8).base64EncodedString(), expect: [235], step: "登录")
        try await command("MAIL FROM:<\(config.username)>", expect: [250], step: "发件人")
        for r in config.recipients {
            try await command("RCPT TO:<\(r)>", expect: [250, 251], step: "收件人 \(r)")
        }
        try await command("DATA", expect: [354], step: "DATA")
        try await transport.write(message + "\r\n.\r\n")
        try await expect([250], step: "发送正文")
        try? await transport.write("QUIT\r\n")
    }

    private func command(_ line: String, expect codes: Set<Int>, step: String) async throws {
        try await transport.write(line + "\r\n")
        try await expect(codes, step: step)
    }

    private func expect(_ codes: Set<Int>, step: String) async throws {
        let (code, message) = try await readReply()
        guard codes.contains(code) else {
            throw SMTPError.unexpectedReply(step: step, code: code, message: message)
        }
    }

    /// 多行回复形如 `250-xxx` … `250 xxx`，第 4 个字符是空格表示最后一行。
    private func readReply() async throws -> (Int, String) {
        var lines: [String] = []
        while true {
            let line = try await transport.readLine()
            lines.append(line)
            let chars = Array(line)
            if chars.count < 4 || chars[3] != "-" {
                let code = Int(String(chars.prefix(3))) ?? 0
                let text = lines.map { String($0.dropFirst(4)) }.joined(separator: " ")
                return (code, text)
            }
        }
    }
}

#if canImport(Network)
import Network

/// 基于 Network.framework 的 TLS 连接。
public final class NWLineTransport: SMTPTransport, @unchecked Sendable {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "dnsmanager.smtp")
    private var buffer = Data()

    public init(host: String, port: Int) {
        let params = NWParameters(tls: NWProtocolTLS.Options())
        connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? 465,
            using: params
        )
    }

    public func open() async throws {
        let connection = self.connection
        let queue = self.queue
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            // 连接状态会变化多次，只有第一次终态 resume。
            let once = OnceFlag()
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { cont.resume() }
                case .failed(let error), .waiting(let error):
                    if once.claim() { cont.resume(throwing: SMTPError.connection(error.localizedDescription)) }
                case .cancelled:
                    if once.claim() { cont.resume(throwing: SMTPError.timeout) }
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
    }

    public func write(_ text: String) async throws {
        let connection = self.connection
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            connection.send(content: Data(text.utf8), completion: .contentProcessed { error in
                if let error {
                    cont.resume(throwing: SMTPError.connection(error.localizedDescription))
                } else {
                    cont.resume()
                }
            })
        }
    }

    public func readLine() async throws -> String {
        let crlf = Data("\r\n".utf8)
        while true {
            if let range = buffer.range(of: crlf) {
                let line = String(decoding: buffer[buffer.startIndex..<range.lowerBound], as: UTF8.self)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return line
            }
            buffer.append(try await receive())
        }
    }

    private func receive() async throws -> Data {
        let connection = self.connection
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                if let error {
                    cont.resume(throwing: SMTPError.connection(error.localizedDescription))
                } else if let data, !data.isEmpty {
                    cont.resume(returning: data)
                } else if isComplete {
                    cont.resume(throwing: SMTPError.connection("服务器关闭了连接"))
                } else {
                    cont.resume(returning: Data())
                }
            }
        }
    }

    public func close() {
        connection.cancel()
    }
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// 第一次调用返回 true，之后都返回 false。
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

public enum Mailer {
    /// 发一封纯文本邮件。超时后直接断开连接，挂起的读写会以错误结束。
    public static func send(
        config: SMTPConfig, subject: String, body: String, timeout: Duration = .seconds(30)
    ) async throws {
        let transport = NWLineTransport(host: config.host, port: config.port)
        let message = MIMEMessage.build(from: config.username, to: config.recipients, subject: subject, body: body)
        let watchdog = Task {
            try await Task.sleep(for: timeout)
            transport.close()
        }
        defer { watchdog.cancel() }
        try await SMTPSession(transport: transport).send(config: config, message: message)
    }
}
#endif
