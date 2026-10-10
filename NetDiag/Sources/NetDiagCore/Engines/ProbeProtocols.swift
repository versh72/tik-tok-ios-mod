import Foundation

/// Resolves host names to addresses.
///
/// Deliberately narrow: it answers "does this name resolve, how fast, and to
/// what addresses" and nothing else. It does not send traffic, does not read
/// the system resolver configuration, and cannot see queries made by other
/// applications.
public protocol DNSResolving: Sendable {
    func resolve(host: String, timeout: TimeInterval) async throws -> [String]
}

/// Performs a TLS handshake and reports what was negotiated.
///
/// The implementation must NOT install a trust override that accepts an
/// invalid certificate. A probe that trusts everything would report success
/// on exactly the broken path it is meant to detect.
public protocol TLSProbing: Sendable {
    func probe(host: String, port: UInt16, serverName: String, timeout: TimeInterval) async throws -> TLSHandshake
}

/// Issues a plain HTTPS request and reports timing and status.
public protocol HTTPSProbing: Sendable {
    func probe(url: URL, timeout: TimeInterval) async throws -> HTTPSExchange
}

/// What a completed TLS handshake yielded.
public struct TLSHandshake: Sendable, Equatable {
    public var protocolName: String?
    public var cipherSuite: String?
    public var certificateSubject: String?
    public var certificateNotBefore: Date?
    public var certificateNotAfter: Date?
    /// Milliseconds spent from opening the connection to handshake completion.
    public var milliseconds: Double

    public init(
        protocolName: String? = nil,
        cipherSuite: String? = nil,
        certificateSubject: String? = nil,
        certificateNotBefore: Date? = nil,
        certificateNotAfter: Date? = nil,
        milliseconds: Double = 0
    ) {
        self.protocolName = protocolName
        self.cipherSuite = cipherSuite
        self.certificateSubject = certificateSubject
        self.certificateNotBefore = certificateNotBefore
        self.certificateNotAfter = certificateNotAfter
        self.milliseconds = milliseconds
    }

    public var expiresInSeconds: Double? {
        guard let notAfter = certificateNotAfter else { return nil }
        return notAfter.timeIntervalSinceNow
    }
}

/// What a completed HTTPS exchange yielded.
public struct HTTPSExchange: Sendable, Equatable {
    public var statusCode: Int
    public var bytesReceived: Int
    public var totalMilliseconds: Double
    public var timeToFirstByteMilliseconds: Double?
    public var redirects: Int

    public init(
        statusCode: Int,
        bytesReceived: Int = 0,
        totalMilliseconds: Double = 0,
        timeToFirstByteMilliseconds: Double? = nil,
        redirects: Int = 0
    ) {
        self.statusCode = statusCode
        self.bytesReceived = bytesReceived
        self.totalMilliseconds = totalMilliseconds
        self.timeToFirstByteMilliseconds = timeToFirstByteMilliseconds
        self.redirects = redirects
    }
}

/// Errors raised by the probes.
///
/// Each case carries enough information to explain what happened without
/// carrying any request payload.
public enum ProbeError: Error, Sendable, Equatable {
    case timedOut(stage: Stage)
    case posix(code: Int32, stage: Stage)
    case urlError(code: Int, stage: Stage)
    case tlsUnavailable(String, stage: Stage)
    case cancelled(stage: Stage)

    public enum Stage: String, Sendable, Equatable {
        case dns, tls, https, path
    }

    public var stage: Stage {
        switch self {
        case .timedOut(let stage), .posix(_, let stage), .urlError(_, let stage),
             .tlsUnavailable(_, let stage), .cancelled(let stage):
            return stage
        }
    }

    /// Raw description, for the report's `systemError` field.
    public var rawDescription: String {
        switch self {
        case .timedOut(let stage):
            return "timeout during \(stage.rawValue)"
        case .posix(let code, let stage):
            return "\(stage.rawValue): \(String(cString: strerror(code))) (errno \(code))"
        case .urlError(let code, let stage):
            return "\(stage.rawValue): URLError \(code)"
        case .tlsUnavailable(let detail, let stage):
            return "\(stage.rawValue): \(detail)"
        case .cancelled(let stage):
            return "\(stage.rawValue): cancelled"
        }
    }

    /// Bucket used for grouping and colouring.
    public func failureKind(using classifier: FailureClassifier) -> FailureKind {
        switch self {
        case .timedOut:
            return .connectionTimedOut
        case .posix(let code, _):
            return classifier.classify(posixError: code)
        case .urlError(let code, _):
            return classifier.classify(urlErrorCode: code)
        case .tlsUnavailable:
            return .tlsHandshakeFailed
        case .cancelled:
            return .cancelled
        }
    }
}