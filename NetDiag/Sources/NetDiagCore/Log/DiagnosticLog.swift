import Foundation

/// A structured, local-only log.
///
/// Every line is redacted on the way in, so a secret cannot reach disk even if
/// it was typed into a field by mistake. The log holds no HTTP headers, no
/// cookies and no request or response bodies, because the probes never collect
/// them in the first place.
public struct DiagnosticLog: Codable, Sendable {

    public struct Entry: Identifiable, Hashable, Codable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let level: Level
        public let message: String
        public let detail: String?

        public enum Level: String, Codable, Sendable, CaseIterable {
            case info, warning, failure, success

            public var localizedName: String {
                switch self {
                case .info:    return DiagnosticsExplainer.text(en: "Info", ru: "Инфо")
                case .warning: return DiagnosticsExplainer.text(en: "Warning", ru: "Внимание")
                case .failure: return DiagnosticsExplainer.text(en: "Failure", ru: "Сбой")
                case .success: return DiagnosticsExplainer.text(en: "OK", ru: "Успех")
                }
            }
        }
    }

    public private(set) var entries: [Entry] = []
    /// Bound on how many lines are kept. Older lines are dropped.
    public var capacity: Int

    public init(capacity: Int = 2000) {
        self.capacity = max(1, capacity)
    }

    /// Appends a line, redacting both the message and the detail.
    @discardableResult
    public mutating func log(
        _ level: Entry.Level,
        _ message: String,
        detail: String? = nil
    ) -> Entry {
        let entry = Entry(
            id: UUID(),
            timestamp: Date(),
            level: level,
            message: Redactor.redactFreeText(message),
            detail: detail.map(Redactor.redactFreeText)
        )
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
        return entry
    }

    public mutating func clear() {
        entries.removeAll()
    }

    /// Plain-text rendering used by the share sheet and the export.
    public func plainText() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return entries
            .map { line in
                let stamp = formatter.string(from: line.timestamp)
                let tail = line.detail.map { " — \($0)" } ?? ""
                return "[\(stamp)] \(line.level.rawValue.uppercased()) \(line.message)\(tail)"
            }
            .joined(separator: "\n")
    }
}