import Foundation

/// A description of the network path the system reported at one moment.
///
/// This is what `NWPathMonitor` exposes to an ordinary app. It is deliberately
/// limited to what Apple documents as public, and it carries no traffic
/// information and no per-application state.
public struct PathSnapshot: Hashable, Codable, Sendable {

    public enum Interface: String, Hashable, Codable, CaseIterable, Sendable {
        case wifi
        case cellular
        case wiredEthernet
        case loopback
        case other
        case unknown
    }

    public var interface: Interface
    public var isExpensive: Bool
    public var isConstrained: Bool
    public var supportsDNS: Bool
    public var supportsIPv4: Bool
    public var supportsIPv6: Bool
    /// Captured at this instant. Used to line up snapshots with results.
    public var capturedAt: Date

    public init(
        interface: Interface = .unknown,
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        supportsDNS: Bool = true,
        supportsIPv4: Bool = true,
        supportsIPv6: Bool = true,
        capturedAt: Date = Date()
    ) {
        self.interface = interface
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.supportsDNS = supportsDNS
        self.supportsIPv4 = supportsIPv4
        self.supportsIPv6 = supportsIPv6
        self.capturedAt = capturedAt
    }

    public var summary: String {
        var parts = [interface.rawValue]
        if isConstrained { parts.append("constrained") }
        if isExpensive { parts.append("expensive") }
        if !supportsIPv4 { parts.append("no-ipv4") }
        if !supportsIPv6 { parts.append("no-ipv6") }
        return parts.joined(separator: ", ")
    }

    /// The honest statement about what this snapshot can and cannot say.
    public var vpnCaveat: String {
        DiagnosticsExplainer.text(
            en: "This snapshot does not report whether a VPN is active. iOS exposes no public API for that to a normal app; recognising a VPN here would be a guess.",
            ru: "Этот снимок не сообщает, активен ли VPN. iOS не предоставляет обычному приложению публичного API для этого; распознать VPN здесь было бы догадкой.")
    }
}

/// The result of probing one target through all three stages.
public struct TargetResult: Identifiable, Hashable, Codable, Sendable {

    public let id: UUID
    public var target: ProbeTarget
    public var dns: DNSReport
    public var tls: TLSReport
    public var https: HTTPSReport
    public var pathAtStart: PathSnapshot
    public var finishedAt: Date

    public init(
        id: UUID = UUID(),
        target: ProbeTarget,
        dns: DNSReport,
        tls: TLSReport,
        https: HTTPSReport,
        pathAtStart: PathSnapshot,
        finishedAt: Date = Date()
    ) {
        self.id = id
        self.target = target
        self.dns = dns
        self.tls = tls
        self.https = https
        self.pathAtStart = pathAtStart
        self.finishedAt = finishedAt
    }

    /// Worst outcome across the three stages, used for row colouring.
    public var overallOutcome: Verdict.Grade {
        Verdict.Grade(worst: dns.outcome.grade, tls.outcome.grade, https.outcome.grade)
    }
}

/// One complete pass over every target in the list.
///
/// Runs are kept so the person using the tool can compare the same target
/// across two network configurations — for example with a tunnel up and then
/// down — which is the comparison that actually answers the question.
public struct DiagnosticRun: Identifiable, Hashable, Codable, Sendable {

    public let id: UUID
    /// Free-form tag, e.g. "VPN on" or "home wifi".
    public var scenario: String
    public var startedAt: Date
    public var finishedAt: Date
    public var pathAtStart: PathSnapshot
    public var pathAtEnd: PathSnapshot
    public var results: [TargetResult]

    public init(
        id: UUID = UUID(),
        scenario: String = "",
        startedAt: Date = Date(),
        finishedAt: Date = Date(),
        pathAtStart: PathSnapshot = PathSnapshot(),
        pathAtEnd: PathSnapshot = PathSnapshot(),
        results: [TargetResult] = []
    ) {
        self.id = id
        self.scenario = scenario
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.pathAtStart = pathAtStart
        self.pathAtEnd = pathAtEnd
        self.results = results
    }

    public var durationMilliseconds: Double {
        finishedAt.timeIntervalSince(startedAt) * 1000
    }

    public var succeededCount: Int {
        results.filter { $0.https.outcome == .completed }.count
    }

    public var failedCount: Int {
        results.count - succeededCount
    }
}

/// The overall read-out of a run.
public enum Verdict {

    /// Per-stage pass/fail, ordered by severity.
    public enum Grade: Int, Comparable, Hashable, Codable, Sendable {
        case skipped = 0
        case passed = 1
        case failed = 2

        public static func < (lhs: Grade, rhs: Grade) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        public var symbolName: String {
            switch self {
            case .passed:  return "checkmark.circle.fill"
            case .failed:  return "xmark.circle.fill"
            case .skipped: return "minus.circle"
            }
        }

        public var localizedName: String {
            switch self {
            case .passed:  return DiagnosticsExplainer.text(en: "Passed", ru: "Успешно")
            case .failed:  return DiagnosticsExplainer.text(en: "Failed", ru: "Ошибка")
            case .skipped: return DiagnosticsExplainer.text(en: "Skipped", ru: "Пропущено")
            }
        }
    }

    /// Combines per-stage grades into one. A failure anywhere wins, because a
    /// TLS failure makes a successful HTTPS grade meaningless.
    public static func Grade(worst stages: Grade...) -> Grade {
        stages.max() ?? .skipped
    }

    /// One-line summary of a run. Deliberately hedged.
    public static func summary(for run: DiagnosticRun) -> String {
        let total = run.results.count
        guard total > 0 else {
            return DiagnosticsExplainer.text(
                en: "No targets were probed.",
                ru: "Цели не проверялись.")
        }
        let ok = run.succeededCount
        let base = DiagnosticsExplainer.text(
            en: "\(ok) of \(total) targets completed a full DNS, TLS and HTTPS pass over \(run.pathAtStart.interface.rawValue).",
            ru: "\(ok) из \(total) целей прошли полный цикл DNS, TLS и HTTPS через \(run.pathAtStart.interface.rawValue).")
        return base + " " + DiagnosticDisclaimer.probeIsNotAppProof
    }
}

extension DNSReport.Outcome {
    var grade: Verdict.Grade {
        switch self {
        case .resolved: return .passed
        case .failed:   return .failed
        case .skipped:  return .skipped
        }
    }
}

extension TLSReport.Outcome {
    var grade: Verdict.Grade {
        switch self {
        case .established: return .passed
        case .failed:      return .failed
        case .skipped:     return .skipped
        }
    }
}

extension HTTPSReport.Outcome {
    var grade: Verdict.Grade {
        switch self {
        case .completed: return .passed
        case .failed:    return .failed
        case .skipped:   return .skipped
        }
    }
}