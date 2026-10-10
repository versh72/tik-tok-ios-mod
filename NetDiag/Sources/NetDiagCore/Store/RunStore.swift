import Foundation

/// Holds finished runs and compares them.
///
/// The comparison is the point of the whole tool: the same target is run
/// twice, once with a tunnel up and once with it down, and the two rows are
/// put side by side. A verdict that only ever looked at one configuration
/// could not tell a device problem from a path problem.
public struct RunComparison: Sendable {

    /// How a single target changed between two runs.
    public struct TargetDelta: Sendable, Identifiable {
        public let id: UUID
        public let label: String
        public let authority: String
        public let beforeGrade: Verdict.Grade
        public let afterGrade: Verdict.Grade
        public let beforeFailureKind: FailureKind?
        public let afterFailureKind: FailureKind?

        public var changed: Bool { beforeGrade != afterGrade }

        /// Human description of the change, or `nil` when nothing changed.
        public var changeDescription: String? {
            guard changed else { return nil }
            let direction = afterGrade > beforeGrade
                ? DiagnosticsExplainer.text(en: "got worse", ru: "ухудшилось")
                : DiagnosticsExplainer.text(en: "got better", ru: "улучшилось")
            var text = "\(beforeGrade.localizedName) → \(afterGrade.localizedName) (\(direction))"
            if let before = beforeFailureKind, let after = afterFailureKind, before != after {
                text += ", bucket `\(before.identifier)` → `\(after.identifier)`"
            }
            return text
        }
    }

    public let baseline: DiagnosticRun
    public let candidate: DiagnosticRun
    public let deltas: [TargetDelta]

    public var changedCount: Int { deltas.filter(\.changed).count }
    public var sameCount: Int { deltas.count - changedCount }
}

/// Compares two runs target-by-target.
public enum RunComparator {

    /// Pairs results by `host:port`, falling back to position for targets that
    /// appear in only one of the two runs.
    public static func compare(
        baseline: DiagnosticRun,
        candidate: DiagnosticRun
    ) -> RunComparison {
        var byKey: [String: TargetResult] = [:]
        for result in baseline.results {
            byKey[result.target.authority] = result
        }

        var deltas: [RunComparison.TargetDelta] = []

        for result in candidate.results {
            let key = result.target.authority
            let before = byKey.removeValue(forKey: key)
            deltas.append(
                RunComparison.TargetDelta(
                    id: result.id,
                    label: result.target.label,
                    authority: key,
                    beforeGrade: before?.overallOutcome ?? .skipped,
                    afterGrade: result.overallOutcome,
                    beforeFailureKind: before?.https.errorKind,
                    afterFailureKind: result.https.errorKind
                )
            )
        }

        // Anything left was only in the baseline.
        for result in byKey.values {
            deltas.append(
                RunComparison.TargetDelta(
                    id: result.id,
                    label: result.target.label,
                    authority: result.target.authority,
                    beforeGrade: result.overallOutcome,
                    afterGrade: .skipped,
                    beforeFailureKind: result.https.errorKind,
                    afterFailureKind: nil
                )
            )
        }

        deltas.sort { $0.authority < $1.authority }
        return RunComparison(baseline: baseline, candidate: candidate, deltas: deltas)
    }
}

/// In-memory store of runs.
///
/// Runs are deliberately not persisted to disk. The tool holds no account
/// data and there is no reason for a diagnostic history to outlive the
/// session it was collected in.
public final class RunStore: @unchecked Sendable {

    private let lock = NSLock()
    private var storage: [DiagnosticRun] = []

    public init() {}

    public var runs: [DiagnosticRun] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    public func append(_ run: DiagnosticRun) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(run)
    }

    public func remove(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll { $0.id == id }
    }

    public func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }

    /// Most recent run, or `nil` when there is none.
    public var latest: DiagnosticRun? { runs.last }

    /// The two most recent runs, if both exist.
    public var lastTwo: (baseline: DiagnosticRun, candidate: DiagnosticRun)? {
        let all = runs
        guard all.count >= 2 else { return nil }
        return (all[all.count - 2], all[all.count - 1])
    }
}