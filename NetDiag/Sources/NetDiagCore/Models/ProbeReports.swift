import Foundation

/// Result of trying to turn a host name into addresses.
public struct DNSReport: Hashable, Codable, Sendable {

    public enum Outcome: String, Hashable, Codable, Sendable {
        case resolved
        case failed
        case skipped
    }

    public var outcome: Outcome
    /// Addresses in presentation order, already truncated by `Redactor`.
    public var addresses: [String]
    public var milliseconds: Double?
    /// Human explanation. Produced by `DiagnosticsExplainer`.
    public var explanation: String
    /// Underlying system error description, if any. Never contains payload data.
    public var systemError: String?

    public init(
        outcome: Outcome,
        addresses: [String] = [],
        milliseconds: Double? = nil,
        explanation: String = "",
        systemError: String? = nil
    ) {
        self.outcome = outcome
        self.addresses = addresses
        self.milliseconds = milliseconds
        self.explanation = explanation
        self.systemError = systemError
    }

    public static let skipped = DNSReport(
        outcome: .skipped,
        explanation: "DNS resolution was not run for this target."
    )
}

/// Result of the TLS handshake probe.
public struct TLSReport: Hashable, Codable, Sendable {

    public enum Outcome: String, Hashable, Codable, Sendable {
        case established
        case failed
        case skipped
    }

    public var outcome: Outcome
    /// Negotiated protocol name, e.g. "tls1.3". `nil` when unknown.
    public var negotiatedProtocol: String?
    /// Negotiated cipher suite name. `nil` when the platform withholds it.
    public var negotiatedCipherSuite: String?
    /// Subject common name from the server leaf certificate, if readable.
    public var certificateSubject: String?
    /// `notBefore` of the leaf certificate, ISO-8601, if readable.
    public var certificateNotBefore: String?
    /// `notAfter` of the leaf certificate, ISO-8601, if readable.
    public var certificateNotAfter: String?
    /// Seconds until `certificateNotAfter`. `nil` when unknown.
    public var certificateExpiresInSeconds: Double?
    public var milliseconds: Double?
    public var explanation: String
    public var systemError: String?

    public init(
        outcome: Outcome,
        negotiatedProtocol: String? = nil,
        negotiatedCipherSuite: String? = nil,
        certificateSubject: String? = nil,
        certificateNotBefore: String? = nil,
        certificateNotAfter: String? = nil,
        certificateExpiresInSeconds: Double? = nil,
        milliseconds: Double? = nil,
        explanation: String = "",
        systemError: String? = nil
    ) {
        self.outcome = outcome
        self.negotiatedProtocol = negotiatedProtocol
        self.negotiatedCipherSuite = negotiatedCipherSuite
        self.certificateSubject = certificateSubject
        self.certificateNotBefore = certificateNotBefore
        self.certificateNotAfter = certificateNotAfter
        self.certificateExpiresInSeconds = certificateExpiresInSeconds
        self.milliseconds = milliseconds
        self.explanation = explanation
        self.systemError = systemError
    }

    public static let skipped = TLSReport(
        outcome: .skipped,
        explanation: "TLS probe was not run for this target."
    )
}

/// Result of the full HTTPS request probe.
public struct HTTPSReport: Hashable, Codable, Sendable {

    public enum Outcome: String, Hashable, Codable, Sendable {
        case completed
        case failed
        case skipped
    }

    public var outcome: Outcome
    /// Bytes of the response body that were read. The body itself is discarded.
    public var bytesReceived: Int?
    public var milliseconds: Double?
    /// Time to first byte, from `URLSessionTaskMetrics`.
    public var timeToFirstByteMilliseconds: Double?
    public var redirects: Int
    /// HTTP status code, when a response was received.
    public var statusCode: Int?
    public var explanation: String
    public var systemError: String?
    /// Symbolic bucket the error maps to, used for grouping in the report.
    public var errorKind: FailureKind?

    public init(
        outcome: Outcome,
        bytesReceived: Int? = nil,
        milliseconds: Double? = nil,
        timeToFirstByteMilliseconds: Double? = nil,
        redirects: Int = 0,
        statusCode: Int? = nil,
        explanation: String = "",
        systemError: String? = nil,
        errorKind: FailureKind? = nil
    ) {
        self.outcome = outcome
        self.bytesReceived = bytesReceived
        self.milliseconds = milliseconds
        self.timeToFirstByteMilliseconds = timeToFirstByteMilliseconds
        self.redirects = redirects
        self.statusCode = statusCode
        self.explanation = explanation
        self.systemError = systemError
        self.errorKind = errorKind
    }

    public static let skipped = HTTPSReport(
        outcome: .skipped,
        explanation: "HTTPS request was not run for this target."
    )
}