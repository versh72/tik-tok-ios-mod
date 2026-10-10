import Foundation

/// Runs the three probe stages against one target and turns whatever happens
/// into a `TargetResult`.
///
/// The stages are independent on purpose:
///
/// * DNS failure is reported as a DNS failure, not as a TLS failure, even
///   though the TLS stage will also fail afterwards. Reporting the first
///   cause is what makes the result actionable.
/// * Each stage failure carries a `FailureKind`, so two runs can be compared
///   by bucket rather than by matching error strings.
public struct ProbeCoordinator: Sendable {

    public struct Configuration: Sendable {
        public var dnsTimeout: TimeInterval
        public var tlsTimeout: TimeInterval
        public var httpsTimeout: TimeInterval
        /// Only as many addresses are carried forward as this many.
        public var maxAddressesRecorded: Int
        /// Bytes of the HTTPS response actually read. The body is discarded;
        /// this bounds the size of the buffer used to drain the connection.
        public var maxBodyBytesRead: Int
        /// Redirects followed by the HTTPS stage.
        public var maxRedirects: Int

        public init(
            dnsTimeout: TimeInterval = 5,
            tlsTimeout: TimeInterval = 8,
            httpsTimeout: TimeInterval = 12,
            maxAddressesRecorded: Int = 4,
            maxBodyBytesRead: Int = 4_096,
            maxRedirects: Int = 5
        ) {
            self.dnsTimeout = dnsTimeout
            self.tlsTimeout = tlsTimeout
            self.httpsTimeout = httpsTimeout
            self.maxAddressesRecorded = maxAddressesRecorded
            self.maxBodyBytesRead = maxBodyBytesRead
            self.maxRedirects = maxRedirects
        }

        public static let `default` = Configuration()
    }

    private let dns: DNSResolving
    private let tls: TLSProbing
    private let https: HTTPSProbing
    private let classifier: FailureClassifier
    private let configuration: Configuration

    public init(
        dns: DNSResolving,
        tls: TLSProbing,
        https: HTTPSProbing,
        classifier: FailureClassifier = FailureClassifier(),
        configuration: Configuration = .default
    ) {
        self.dns = dns
        self.tls = tls
        self.https = https
        self.classifier = classifier
        self.configuration = configuration
    }

    /// Probes a single target.
    ///
    /// Never throws: every outcome is folded into the returned value, because
    /// a failing probe is a result, not an exception the caller has to handle.
    public func probe(_ target: ProbeTarget, path: PathSnapshot) async -> TargetResult {
        let start = Date()

        // Stage 1 — DNS.
        let dnsStart = Date()
        var addresses: [String] = []
        var dnsReport: DNSReport

        do {
            let resolved = try await dns.resolve(
                host: target.host,
                timeout: configuration.dnsTimeout
            )
            addresses = Array(resolved.prefix(configuration.maxAddressesRecorded))
            let elapsed = Date().timeIntervalSince(dnsStart) * 1000
            if addresses.isEmpty {
                dnsReport = DNSReport(
                    outcome: .failed,
                    addresses: [],
                    milliseconds: elapsed,
                    explanation: DiagnosticsExplainer.text(
                        en: "Resolution returned no addresses.",
                        ru: "Разрешение не вернуло ни одного адреса."),
                    systemError: "no addresses"
                )
            } else {
                dnsReport = DNSReport(
                    outcome: .resolved,
                    addresses: addresses,
                    milliseconds: elapsed,
                    explanation: DiagnosticsExplainer.text(
                        en: "Resolved to \(resolved.count) address(es).",
                        ru: "Разрешено в \(resolved.count) адрес(ов).")
                )
            }
        } catch {
            let elapsed = Date().timeIntervalSince(dnsStart) * 1000
            let kind = kindOf(error)
            dnsReport = DNSReport(
                outcome: .failed,
                addresses: [],
                milliseconds: elapsed,
                explanation: classifier.explain(kind),
                systemError: describe(error)
            )
        }

        // Stage 2 — TLS.
        var tlsReport = TLSReport.skipped
        if dnsReport.outcome == .resolved {
            tlsReport = await runTLS(target: target, startedAt: start)
        }

        // Stage 3 — HTTPS.
        var httpsReport = HTTPSReport.skipped
        if tlsReport.outcome == .established, let url = target.url {
            httpsReport = await runHTTPS(url: url, target: target)
        }

        return TargetResult(
            target: target,
            dns: dnsReport,
            tls: tlsReport,
            https: httpsReport,
            pathAtStart: path,
            finishedAt: Date()
        )
    }

    // MARK: - Stages

    private func runTLS(target: ProbeTarget, startedAt: Date) async -> TLSReport {
        let stageStart = Date()
        do {
            let handshake = try await tls.probe(
                host: target.host,
                port: target.port,
                serverName: target.host,
                timeout: configuration.tlsTimeout
            )
            return TLSReport(
                outcome: .established,
                negotiatedProtocol: handshake.protocolName,
                negotiatedCipherSuite: handshake.cipherSuite,
                certificateSubject: handshake.certificateSubject,
                certificateNotBefore: handshake.certificateNotBefore.map(iso8601),
                certificateNotAfter: handshake.certificateNotAfter.map(iso8601),
                certificateExpiresInSeconds: handshake.expiresInSeconds,
                milliseconds: Date().timeIntervalSince(stageStart) * 1000,
                explanation: DiagnosticsExplainer.text(
                    en: "The TLS handshake completed and the system accepted the certificate.",
                    ru: "TLS-рукопожатие завершено, система приняла сертификат.")
            )
        } catch {
            let kind = kindOf(error)
            return TLSReport(
                outcome: .failed,
                milliseconds: Date().timeIntervalSince(stageStart) * 1000,
                explanation: classifier.explain(kind),
                systemError: describe(error)
            )
        }
    }

    private func runHTTPS(url: URL, target: ProbeTarget) async -> HTTPSReport {
        let stageStart = Date()
        do {
            let exchange = try await https.probe(url: url, timeout: configuration.httpsTimeout)
            return HTTPSReport(
                outcome: .completed,
                bytesReceived: exchange.bytesReceived,
                milliseconds: Date().timeIntervalSince(stageStart) * 1000,
                timeToFirstByteMilliseconds: exchange.timeToFirstByteMilliseconds,
                redirects: exchange.redirects,
                statusCode: exchange.statusCode,
                explanation: DiagnosticsExplainer.text(
                    en: "The request completed. The response body was read and discarded.",
                    ru: "Запрос завершён. Тело ответа прочитано и отброшено.")
            )
        } catch {
            let kind = kindOf(error)
            return HTTPSReport(
                outcome: .failed,
                milliseconds: Date().timeIntervalSince(stageStart) * 1000,
                explanation: classifier.explain(kind),
                systemError: describe(error),
                errorKind: kind
            )
        }
    }

    // MARK: - Helpers

    private func kindOf(_ error: Error) -> FailureKind {
        if let probeError = error as? ProbeError {
            return probeError.failureKind(using: classifier)
        }
        if let urlError = error as? URLError {
            return classifier.classify(urlError: urlError)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return classifier.classify(urlErrorCode: nsError.code)
        }
        if nsError.domain == NSPOSIXErrorDomain {
            return classifier.classify(posixError: nsError.code)
        }
        return classifier.classify(description: nsError.localizedDescription)
    }

    private func describe(_ error: Error) -> String {
        if let probeError = error as? ProbeError {
            return probeError.rawDescription
        }
        return Redactor.redactFreeText((error as NSError).localizedDescription)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}