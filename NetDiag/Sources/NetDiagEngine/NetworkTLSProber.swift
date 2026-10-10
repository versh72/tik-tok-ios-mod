import Foundation
import Network
import Security
import NetDiagCore

/// TLS handshake probe built on `NWConnection`.
///
/// Design note that matters more than anything else in this file: the probe
/// does **not** accept every certificate.
///
/// A tool that disabled trust evaluation would report "TLS fine" on exactly
/// the broken path this app exists to detect — a tunnel that terminates TLS
/// and presents its own certificate would look healthy. So the verify block
/// runs the system's own evaluation and, when it fails, records *why* and
/// passes that reason out with the error. The diagnosis is the result; it is
/// not something to work around.
public struct NetworkTLSProber: TLSProbing {

    private let queue = DispatchQueue(label: "netdiag.tls", qos: .utility)

    public init() {}

    public func probe(
        host: String,
        port: UInt16,
        serverName: String,
        timeout: TimeInterval
    ) async throws -> TLSHandshake {

        let started = DispatchTime.now()
        // Shared between the verify block (on the connection queue) and the
        // state handler. Both already run on `queue`, but the compiler does
        // not know that, so the mutable state lives behind a lock.
        let box = HandshakeBox()

        return try await withCheckedThrowingContinuation { continuation in
            let gate = TLSResumeGate()

            let tlsOptions = NWProtocolTLS.Options()
            sec_protocol_options_set_min_tls_protocol_version(
                tlsOptions.securityProtocolOptions,
                .TLSv12
            )

            sec_protocol_options_set_verify_block(
                tlsOptions.securityProtocolOptions,
                { [queue] metadata, secTrust, complete in
                    let verdict = Self.evaluate(metadata: metadata, secTrust: secTrust)
                    box.record(verdict)
                    // The system's decision is passed straight through, not
                    // replaced by a blanket `true`.
                    complete(verdict.isAcceptable)
                },
                queue
            )

            let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
            parameters.prohibitExpensivePaths = false
            parameters.prohibitConstrainedPaths = false
            parameters.serviceClass = .responsiveData

            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(serverName),
                port: NWEndpoint.Port(rawValue: port) ?? .https
            )
            let connection = NWConnection(to: endpoint, using: parameters)

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    var result = box.handshake()
                    result.milliseconds = Self.elapsedMilliseconds(since: started)
                    gate.resumeOnce { continuation.resume(returning: result) }

                case .failed(let error):
                    connection.cancel()
                    // If the handshake got far enough to produce a verdict,
                    // its reason is more useful than the generic NWError.
                    let thrown: ProbeError = box.failureReason()
                        .map { .tlsUnavailable($0, stage: .tls) }
                        ?? Self.describe(error)
                    gate.resumeOnce { continuation.resume(throwing: thrown) }

                case .cancelled:
                    // Reached on the normal path, after `connection.cancel()`
                    // above. The continuation is already settled.
                    break

                default:
                    break
                }
            }

            connection.start(queue: queue)

            queue.asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
                gate.resumeOnce { continuation.resume(throwing: ProbeError.timedOut(stage: .tls)) }
            }
        }
    }

    private static func elapsedMilliseconds(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    // MARK: - Verify block

    /// Facts collected in the verify block.
    struct HandshakeVerdict {
        var isAcceptable = false
        var protocolName: String?
        var cipherSuite: String?
        var certificateSubject: String?
        var certificateNotBefore: Date?
        var certificateNotAfter: Date?
        var failureReason: String?
    }

    private static func evaluate(
        metadata: sec_protocol_metadata,
        secTrust: sec_trust
    ) -> HandshakeVerdict {
        var verdict = HandshakeVerdict()

        // Negotiated parameters are available even when trust fails, which is
        // exactly the case worth reporting.
        if let negotiated = sec_protocol_metadata_get_negotiated_protocol(metadata) {
            verdict.protocolName = String(cString: negotiated)
        }

        let suite = sec_protocol_metadata_get_negotiated_tls_ciphersuite(metadata)
        if let name = tls_ciphersuite_name(suite) {
            verdict.cipherSuite = String(cString: name)
        } else {
            verdict.cipherSuite = String(format: "0x%04x", suite.rawValue)
        }

        let trust = sec_trust_copy_ref(secTrust).takeRetainedValue()

        if let leaf = SecTrustGetCertificateAtIndex(trust, 0) {
            if let summary = SecCertificateCopySubjectSummary(leaf) as String? {
                verdict.certificateSubject = summary
            }
            let validity = certificateValidity(leaf)
            verdict.certificateNotBefore = validity.notBefore
            verdict.certificateNotAfter = validity.notAfter
        }

        // The system's own decision. Not overridden.
        var trustError: CFError?
        if SecTrustEvaluateWithError(trust, &trustError) {
            verdict.isAcceptable = true
            verdict.failureReason = nil
        } else {
            verdict.isAcceptable = false
            verdict.failureReason = describeTrustFailure(trust, error: trustError)
        }

        return verdict
    }

    /// Prefers the per-certificate evaluation result over the coarse error
    /// copy, because "expired" and "untrusted root" read very differently to
    /// the person trying to work out what is wrong.
    private static func describeTrustFailure(_ trust: SecTrust, error: CFError?) -> String {
        var parts: [String] = []

        if #available(iOS 15.0, macOS 12.0, *),
           let result = SecTrustCopyResult(trust) as? [String: Any],
           let type = result[kSecTrustResultType as String] as? String,
           !type.isEmpty {
            parts.append(type)
        }

        if let message = (error as Error?)?.localizedDescription, !message.isEmpty {
            parts.append(message)
        }

        return parts.isEmpty
            ? "the system rejected the server certificate"
            : parts.joined(separator: " — ")
    }

    /// Reads the validity window of a certificate.
    ///
    /// `SecCertificateCopyValues` is the only public API that exposes the
    /// notBefore/notAfter pair without parsing ASN.1 by hand. Apple has marked
    /// it deprecated, so this may produce a build warning; it is kept because
    /// certificate expiry is one of the conditions the tool is meant to catch.
    private static func certificateValidity(
        _ certificate: SecCertificate
    ) -> (notBefore: Date?, notAfter: Date?) {

        let keys = [kSecOIDX509V1ValidityNotBefore, kSecOIDX509V1ValidityNotAfter] as CFArray

        guard let raw = SecCertificateCopyValues(certificate, keys, nil),
              let values = raw as? [String: Any]
        else { return (nil, nil) }

        func date(for oid: CFString) -> Date? {
            guard let entry = values[oid as String] as? [String: Any],
                  let value = entry[kSecPropertyKeyValue as String]
            else { return nil }

            // The property is a CFAbsoluteTime, which bridges to a Double.
            if let seconds = value as? TimeInterval {
                return Date(timeIntervalSinceReferenceDate: seconds)
            }
            if let number = value as? NSNumber {
                return Date(timeIntervalSinceReferenceDate: number.doubleValue)
            }
            return nil
        }

        return (date(for: kSecOIDX509V1ValidityNotBefore),
                date(for: kSecOIDX509V1ValidityNotAfter))
    }

    private static func describe(_ error: NWError) -> ProbeError {
        switch error {
        case .posix(let code):
            return .posix(code: code.rawValue, stage: .tls)
        case .dns(let dnsError):
            return .posix(code: dnsError.posixCode.rawValue, stage: .dns)
        case .tls(let status):
            return .tlsUnavailable(
                "TLS status \(status.rawValue) (\(tlsStatusName(status)))",
                stage: .tls
            )
        @unknown default:
            return .tlsUnavailable("unrecognised NWError", stage: .tls)
        }
    }

    private static func tlsStatusName(_ status: NWProtocolTLS.Status) -> String {
        switch status {
        case .negotiationFailed:           return "negotiationFailed"
        case .peerCertificateChainInvalid: return "peerCertificateChainInvalid"
        case .peerCertificateExpired:      return "peerCertificateExpired"
        case .peerCertificateUnknownRoot:  return "peerCertificateUnknownRoot"
        case .peerCertificateRevoked:      return "peerCertificateRevoked"
        case .peerCertificateNotYetValid:  return "peerCertificateNotYetValid"
        case .peerCertificateRejected:     return "peerCertificateRejected"
        default:                            return "other"
        }
    }
}

/// Mutable handshake state shared between the verify block and the state
/// handler. Both callbacks run on the connection's queue, but the compiler
/// cannot prove it, so access goes through a lock.
private final class HandshakeBox: @unchecked Sendable {

    private let lock = NSLock()
    private var verdict = NetworkTLSProber.HandshakeVerdict()

    func record(_ value: NetworkTLSProber.HandshakeVerdict) {
        lock.lock()
        verdict = value
        lock.unlock()
    }

    /// Facts from the verify block, as a handshake result.
    func handshake() -> TLSHandshake {
        lock.lock()
        defer { lock.unlock() }
        return TLSHandshake(
            protocolName: verdict.protocolName,
            cipherSuite: verdict.cipherSuite,
            certificateSubject: verdict.certificateSubject,
            certificateNotBefore: verdict.certificateNotBefore,
            certificateNotAfter: verdict.certificateNotAfter,
            milliseconds: 0
        )
    }

    /// Why the system rejected the certificate, when it did.
    func failureReason() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return verdict.failureReason
    }
}

/// Makes a continuation resume exactly once.
private final class TLSResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    func resumeOnce(_ body: () -> Void) {
        lock.lock()
        if used {
            lock.unlock()
            return
        }
        used = true
        lock.unlock()
        body()
    }
}