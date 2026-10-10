import XCTest
@testable import NetDiagCore

final class DiagnosticLogTests: XCTestCase {

    func testEntriesAreAppendedInOrder() {
        var log = DiagnosticLog()
        log.log(.info, "first")
        log.log(.warning, "second")

        XCTAssertEqual(log.entries.count, 2)
        XCTAssertEqual(log.entries[0].message, "first")
        XCTAssertEqual(log.entries[1].message, "second")
    }

    func testCapacityDropsOldestEntries() {
        var log = DiagnosticLog(capacity: 3)
        for index in 0..<10 {
            log.log(.info, "entry \(index)")
        }

        XCTAssertEqual(log.entries.count, 3)
        XCTAssertEqual(log.entries.first?.message, "entry 7")
        XCTAssertEqual(log.entries.last?.message, "entry 9")
    }

    func testCapacityOfZeroIsClampedToOne() {
        var log = DiagnosticLog(capacity: 0)
        log.log(.info, "only")
        XCTAssertEqual(log.entries.count, 1)
    }

    func testSecretsAreRedactedOnTheWayIn() {
        var log = DiagnosticLog()
        log.log(.failure, "token=LEAKME123 failed")
        log.log(.info, "mail me at a@b.com", detail: "password=hunter2")

        let text = log.plainText()
        XCTAssertFalse(text.contains("LEAKME123"), "secret reached the log")
        XCTAssertFalse(text.contains("a@b.com"), "e-mail reached the log")
        XCTAssertFalse(text.contains("hunter2"), "detail was not redacted")
    }

    func testPlainTextIncludesLevelAndDetail() {
        var log = DiagnosticLog()
        log.log(.success, "ok", detail: "42 passed")

        let text = log.plainText()
        XCTAssertTrue(text.contains("SUCCESS"))
        XCTAssertTrue(text.contains("42 passed"))
    }

    func testClearEmptiesTheLog() {
        var log = DiagnosticLog()
        log.log(.info, "something")
        log.clear()
        XCTAssertTrue(log.entries.isEmpty)
        XCTAssertTrue(log.plainText().isEmpty)
    }

    func testEveryLevelHasALocalisedName() {
        for level in DiagnosticLog.Entry.Level.allCases {
            XCTAssertFalse(level.localizedName.isEmpty)
        }
    }
}

final class RunComparatorTests: XCTestCase {

    private func result(
        host: String,
        dns: DNSReport.Outcome,
        tls: TLSReport.Outcome,
        kind: FailureKind? = nil
    ) -> TargetResult {
        let httpsOutcome: HTTPSReport.Outcome = (tls == .established) ? .completed : .skipped
        return TargetResult(
            target: ProbeTarget(label: host, host: host),
            dns: DNSReport(outcome: dns),
            tls: TLSReport(outcome: tls),
            https: HTTPSReport(outcome: httpsOutcome, errorKind: kind),
            pathAtStart: PathSnapshot()
        )
    }

    private func run(_ scenario: String, _ results: [TargetResult]) -> DiagnosticRun {
        DiagnosticRun(scenario: scenario, results: results)
    }

    func testUnchangedTargetsAreReportedAsUnchanged() {
        let baseline = run("VPN off", [result(host: "a.com", dns: .resolved, tls: .established)])
        let candidate = run("VPN on", [result(host: "a.com", dns: .resolved, tls: .established)])

        let comparison = RunComparator.compare(baseline: baseline, candidate: candidate)

        XCTAssertEqual(comparison.deltas.count, 1)
        XCTAssertFalse(comparison.deltas[0].changed)
        XCTAssertEqual(comparison.changedCount, 0)
        XCTAssertEqual(comparison.sameCount, 1)
        XCTAssertNil(comparison.deltas[0].changeDescription)
    }

    func testRegressionIsDetected() {
        // The whole point of the comparison screen: same target, one
        // configuration working and the other not.
        let baseline = run("VPN off", [result(host: "a.com", dns: .resolved, tls: .established)])
        let candidate = run("VPN on", [
            result(host: "a.com", dns: .resolved, tls: .failed, kind: .tlsCertificateRejected)
        ])

        let comparison = RunComparator.compare(baseline: baseline, candidate: candidate)

        XCTAssertEqual(comparison.changedCount, 1)
        let change = comparison.deltas[0].changeDescription
        XCTAssertNotNil(change)
        XCTAssertTrue(change!.contains("tlsCertificateRejected"), change!)
    }

    func testImprovementIsReportedAsSuch() {
        let baseline = run("VPN on", [
            result(host: "a.com", dns: .resolved, tls: .failed, kind: .connectionTimedOut)
        ])
        let candidate = run("VPN off", [result(host: "a.com", dns: .resolved, tls: .established)])

        let change = RunComparator.compare(baseline: baseline, candidate: candidate)
            .deltas[0].changeDescription
        XCTAssertNotNil(change)
        XCTAssertTrue(change!.lowercased().contains("got better"), change!)
    }

    func testBucketChangeIsCalledOut() {
        let baseline = run("A", [result(host: "a.com", dns: .resolved, tls: .failed, kind: .connectionTimedOut)])
        let candidate = run("B", [result(host: "a.com", dns: .failed, tls: .skipped, kind: .dnsResolutionFailed)])

        let change = RunComparator.compare(baseline: baseline, candidate: candidate)
            .deltas[0].changeDescription
        XCTAssertTrue(change!.contains("connectionTimedOut"), change!)
        XCTAssertTrue(change!.contains("dnsResolutionFailed"), change!)
    }

    func testTargetOnlyInBaselineIsStillListed() {
        let baseline = run("A", [
            result(host: "a.com", dns: .resolved, tls: .established),
            result(host: "gone.com", dns: .resolved, tls: .established)
        ])
        let candidate = run("B", [result(host: "a.com", dns: .resolved, tls: .established)])

        let comparison = RunComparator.compare(baseline: baseline, candidate: candidate)
        XCTAssertEqual(comparison.deltas.count, 2)
        XCTAssertTrue(comparison.deltas.contains { $0.authority == "gone.com" })
    }

    func testDeltasAreSortedForStableRendering() {
        let baseline = run("A", [
            result(host: "z.com", dns: .resolved, tls: .established),
            result(host: "a.com", dns: .resolved, tls: .established)
        ])
        let candidate = run("B", [
            result(host: "z.com", dns: .resolved, tls: .established),
            result(host: "a.com", dns: .resolved, tls: .established)
        ])

        let authorities = RunComparator.compare(baseline: baseline, candidate: candidate)
            .deltas.map(\.authority)
        XCTAssertEqual(authorities, authorities.sorted())
    }
}

final class RunStoreTests: XCTestCase {

    func testRunsAreKeptInOrder() {
        let store = RunStore()
        let first = DiagnosticRun(scenario: "one")
        let second = DiagnosticRun(scenario: "two")

        store.append(first)
        store.append(second)

        XCTAssertEqual(store.runs.map(\.scenario), ["one", "two"])
        XCTAssertEqual(store.latest?.scenario, "two")
    }

    func testLastTwoRequiresAtLeastTwoRuns() {
        let store = RunStore()
        XCTAssertNil(store.lastTwo)

        store.append(DiagnosticRun(scenario: "one"))
        XCTAssertNil(store.lastTwo, "a single run cannot be compared with itself")

        store.append(DiagnosticRun(scenario: "two"))
        let pair = store.lastTwo
        XCTAssertEqual(pair?.baseline.scenario, "one")
        XCTAssertEqual(pair?.candidate.scenario, "two")
    }

    func testRemoveAndClearWork() {
        let store = RunStore()
        let run = DiagnosticRun(scenario: "one")
        store.append(run)
        store.append(DiagnosticRun(scenario: "two"))

        store.remove(run.id)
        XCTAssertEqual(store.runs.count, 1)

        store.removeAll()
        XCTAssertTrue(store.runs.isEmpty)
    }
}

final class PresetTargetTests: XCTestCase {

    func testEveryPresetIsAValidTarget() throws {
        for preset in PresetTargets.all {
            XCTAssertNoThrow(
                try EndpointValidator.validateHost(preset.target.host),
                "preset \(preset.id) has an invalid host"
            )
            XCTAssertEqual(preset.target.port, 443)
            XCTAssertFalse(preset.target.host.isEmpty, "preset \(preset.id) has no host")
        }
    }

    func testEveryPresetExplainsItsPurpose() {
        for preset in PresetTargets.all {
            XCTAssertFalse(preset.purpose.isEmpty, "preset \(preset.id) has no purpose text")
        }
    }

    func testPresetIdentifiersAreUnique() {
        let ids = PresetTargets.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate preset identifier")
    }
}