import Foundation

/// Turns a run into something shareable.
///
/// The output is deliberately plain: JSON for machine reading and Markdown for
/// a human pasting it into a support thread. Both go through `Redactor`, and
/// the report carries the standing disclaimer so a report cannot be read as a
/// claim about any particular application.
public struct ReportBuilder {

    public struct Report: Sendable {
        public let json: String
        public let markdown: String
    }

    private let formatter: ISO8601DateFormatter

    public init() {
        formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
    }

    // MARK: - Markdown

    public func markdown(for run: DiagnosticRun) -> String {
        var out = "# Network diagnostic report\n\n"
        out += "- Generated: \(formatter.string(from: run.finishedAt))\n"
        out += "- Scenario: \(Redactor.redact(run.scenario).isEmpty ? "(unnamed)" : Redactor.redact(run.scenario))\n"
        out += "- Duration: \(Int(run.durationMilliseconds)) ms\n"
        out += "- Path at start: \(run.pathAtStart.summary)\n"
        out += "- Path at end: \(run.pathAtEnd.summary)\n"
        out += "- Targets: \(run.succeededCount) passed, \(run.failedCount) failed\n\n"

        out += "> \(DiagnosticDisclaimer.probeIsNotAppProof)\n"
        out += ">\n"
        out += "> \(DiagnosticDisclaimer.noTrafficInspection)\n\n"

        out += "## Summary\n\n"
        out += Verdict.summary(for: run) + "\n\n"

        out += "## Targets\n\n"
        for result in run.results {
            out += "### \(Redactor.redact(result.target.label)) — `\(result.target.authority)`\n\n"
            let note = Redactor.redact(result.target.note)
            if !note.isEmpty { out += "> Note: \(note)\n\n" }

            out += stageTable(for: result)
            out += "\n"

            let lines = [result.dns.explanation, result.tls.explanation, result.https.explanation]
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                out += lines.map { "- \($0)" }.joined(separator: "\n") + "\n\n"
            }

            if result.https.errorKind != nil {
                out += "Failure bucket: `\(result.https.errorKind?.identifier ?? "unknown")`\n\n"
            }
        }

        out += "## Path caveat\n\n"
        out += run.pathAtStart.vpnCaveat + "\n"
        return out
    }

    private func stageTable(for result: TargetResult) -> String {
        var out = "| Stage | Outcome | Detail |\n"
        out += "|---|---|---|\n"

        let dnsDetail: String
        switch result.dns.outcome {
        case .resolved:
            dnsDetail = result.dns.addresses.joined(separator: ", ")
                + (result.dns.milliseconds.map { " (\(Int($0)) ms)" } ?? "")
        case .failed:
            dnsDetail = result.dns.systemError ?? "—"
        case .skipped:
            dnsDetail = "—"
        }
        out += "| DNS | \(result.dns.outcome.rawValue) | \(escapePipes(dnsDetail)) |\n"

        let tlsDetail: String
        switch result.tls.outcome {
        case .established:
            var parts: [String] = []
            if let proto = result.tls.negotiatedProtocol { parts.append(proto) }
            if let cipher = result.tls.negotiatedCipherSuite { parts.append(cipher) }
            if let subject = result.tls.certificateSubject { parts.append("CN=\(subject)") }
            if let expiry = result.tls.certificateExpiresInSeconds {
                parts.append("expires in \(formatDuration(expiry))")
            }
            tlsDetail = parts.isEmpty ? "handshake complete" : parts.joined(separator: ", ")
        case .failed:
            tlsDetail = result.tls.systemError ?? "—"
        case .skipped:
            tlsDetail = "—"
        }
        out += "| TLS | \(result.tls.outcome.rawValue) | \(escapePipes(tlsDetail)) |\n"

        let httpsDetail: String
        switch result.https.outcome {
        case .completed:
            httpsDetail = [
                result.https.statusCode.map { "HTTP \($0)" },
                result.https.timeToFirstByteMilliseconds.map { "ttfb \(Int($0)) ms" },
                result.https.milliseconds.map { "total \(Int($0)) ms" },
                result.https.bytesReceived.map { "\($0) bytes" },
                result.https.redirects > 0 ? "\(result.https.redirects) redirects" : nil
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
        case .failed:
            httpsDetail = result.https.systemError ?? "—"
        case .skipped:
            httpsDetail = "—"
        }
        out += "| HTTPS | \(result.https.outcome.rawValue) | \(escapePipes(httpsDetail)) |\n"

        return out
    }

    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 0 { return "expired" }
        let days = Int(seconds / 86_400)
        if days > 0 { return "\(days)d" }
        let hours = Int(seconds / 3_600)
        if hours > 0 { return "\(hours)h" }
        return "\(Int(seconds / 60))m"
    }

    private func escapePipes(_ text: String) -> String {
        text.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }

    // MARK: - JSON

    /// Encodes the run as JSON with every user-controlled string redacted.
    public func json(for run: DiagnosticRun) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(RedactedRun(run: run)), as: UTF8.self)
    }

    /// Runs both renderings, dropping the JSON one if it cannot be produced
    /// rather than failing the whole export.
    public func report(for run: DiagnosticRun) -> Report {
        let md = markdown(for: run)
        let json = (try? json(for: run)) ?? "// JSON encoding failed; see Markdown output."
        return Report(json: json, markdown: md)
    }
}

/// A run with every user-controlled string passed through `Redactor`.
///
/// Only the fields a person typed can carry a secret. Host names, outcomes,
/// timings and certificate subjects come from the network stack, not from the
/// user, so they are left intact — that is what makes the report useful.
struct RedactedRun: Encodable {

    struct Target: Encodable {
        let label: String
        let host: String
        let port: Int
        let path: String
        let scenario: String
        let note: String
    }

    struct DNS: Encodable {
        let outcome: String
        let addresses: [String]
        let milliseconds: Double?
        let explanation: String
        let systemError: String?
    }

    struct TLS: Encodable {
        let outcome: String
        let protocolName: String?
        let cipherSuite: String?
        let certificateSubject: String?
        let certificateNotBefore: String?
        let certificateNotAfter: String?
        let certificateExpiresInSeconds: Double?
        let milliseconds: Double?
        let explanation: String
        let systemError: String?
    }

    struct HTTPS: Encodable {
        let outcome: String
        let statusCode: Int?
        let bytesReceived: Int?
        let timeToFirstByteMilliseconds: Double?
        let milliseconds: Double?
        let redirects: Int
        let explanation: String
        let systemError: String?
        let failureKind: String?
    }

    struct Path: Encodable {
        let interface: String
        let isExpensive: Bool
        let isConstrained: Bool
        let supportsDNS: Bool
        let supportsIPv4: Bool
        let supportsIPv6: Bool
        let capturedAt: Date

        init(_ snapshot: PathSnapshot) {
            interface = snapshot.interface.rawValue
            isExpensive = snapshot.isExpensive
            isConstrained = snapshot.isConstrained
            supportsDNS = snapshot.supportsDNS
            supportsIPv4 = snapshot.supportsIPv4
            supportsIPv6 = snapshot.supportsIPv6
            capturedAt = snapshot.capturedAt
        }
    }

    struct Outcome: Encodable {
        let target: Target
        let dns: DNS
        let tls: TLS
        let https: HTTPS
        let pathAtStart: Path
        let finishedAt: Date
    }

    let id: String
    let scenario: String
    let startedAt: Date
    let finishedAt: Date
    let pathAtStart: Path
    let pathAtEnd: Path
    let summary: String
    let disclaimerProbeIsNotAppProof: String
    let disclaimerNoTrafficInspection: String
    let disclaimerVpnNotObservable: String
    let results: [Outcome]

    init(run: DiagnosticRun) {
        id = run.id.uuidString
        scenario = Redactor.redact(run.scenario)
        startedAt = run.startedAt
        finishedAt = run.finishedAt
        pathAtStart = Path(run.pathAtStart)
        pathAtEnd = Path(run.pathAtEnd)
        summary = Verdict.summary(for: run)
        disclaimerProbeIsNotAppProof = DiagnosticDisclaimer.probeIsNotAppProof
        disclaimerNoTrafficInspection = DiagnosticDisclaimer.noTrafficInspection
        disclaimerVpnNotObservable = run.pathAtStart.vpnCaveat
        results = run.results.map { result in
            Outcome(
                target: Target(
                    label: Redactor.redact(result.target.label),
                    host: result.target.host,
                    port: Int(result.target.port),
                    path: Redactor.redact(result.target.path),
                    scenario: Redactor.redact(result.target.scenario),
                    note: Redactor.redact(result.target.note)
                ),
                dns: DNS(
                    outcome: result.dns.outcome.rawValue,
                    addresses: result.dns.addresses,
                    milliseconds: result.dns.milliseconds,
                    explanation: result.dns.explanation,
                    systemError: result.dns.systemError.map(Redactor.redact)
                ),
                tls: TLS(
                    outcome: result.tls.outcome.rawValue,
                    protocolName: result.tls.negotiatedProtocol,
                    cipherSuite: result.tls.negotiatedCipherSuite,
                    certificateSubject: result.tls.certificateSubject,
                    certificateNotBefore: result.tls.certificateNotBefore,
                    certificateNotAfter: result.tls.certificateNotAfter,
                    certificateExpiresInSeconds: result.tls.certificateExpiresInSeconds,
                    milliseconds: result.tls.milliseconds,
                    explanation: result.tls.explanation,
                    systemError: result.tls.systemError.map(Redactor.redact)
                ),
                https: HTTPS(
                    outcome: result.https.outcome.rawValue,
                    statusCode: result.https.statusCode,
                    bytesReceived: result.https.bytesReceived,
                    timeToFirstByteMilliseconds: result.https.timeToFirstByteMilliseconds,
                    milliseconds: result.https.milliseconds,
                    redirects: result.https.redirects,
                    explanation: result.https.explanation,
                    systemError: result.https.systemError.map(Redactor.redact),
                    failureKind: result.https.errorKind?.identifier
                ),
                pathAtStart: Path(result.pathAtStart),
                finishedAt: result.finishedAt
            )
        }
    }
}