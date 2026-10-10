import XCTest
@testable import NetDiagCore

final class ReportBuilderTests: XCTestCase {

    private let builder = ReportBuilder()

    private func sampleRun(
        scenario: String = "VPN on",
        label: String = "Example",
        note: String = "",
        dns: DNSReport = DNSReport(outcome: .resolved, addresses: ["93.184.216.34"],
                                   milliseconds: 12, explanation: "Resolved."),
        tls: TLSReport = TLSReport(outcome: .established, negotiatedProtocol: "tls1.3",
                                   certificateSubject: "example.com", milliseconds: 40,
                                   explanation: "Handshake complete."),
        https: HTTPSReport = HTTPSReport(outcome: .completed, statusCode: 200,
                                         bytesReceived: 0, milliseconds: 90,
                                         timeToFirstByteMilliseconds: 30,
                                         explanation: "Request completed.")
    ) -> DiagnosticRun {
        let target = ProbeTarget(label: label, host: "example.com", scenario: scenario, note: note)
        return DiagnosticRun(
            scenario: scenario,
            pathAtStart: PathSnapshot(interface: .wifi),
            pathAtEnd: PathSnapshot(interface: .wifi),
            results: [
                TargetResult(target: target, dns: dns, tls: tls, https: https,
                             pathAtStart: PathSnapshot(interface: .wifi))
            ]
        )
    }

    // MARK: - Disclaimer

    func testMarkdownAlwaysCarriesTheProbeDisclaimer() {
        let markdown = builder.markdown(for: sampleRun())
        XCTAssertTrue(markdown.contains("does not establish"))
    }

    func testJSONAlwaysCarriesTheDisclaimerFields() throws {
        let json = try builder.json(for: sampleRun())
        XCTAssertTrue(json.contains("disclaimerProbeIsNotAppProof"))
        XCTAssertTrue(json.contains("disclaimerNoTrafficInspection"))
        XCTAssertTrue(json.contains("disclaimerVpnNotObservable"))
    }

    func testMarkdownStatesTheToolDoesNotInspectOtherTraffic() {
        XCTAssertTrue(builder.markdown(for: sampleRun()).contains("does not read, log, intercept"))
    }

    // MARK: - Redaction

    func testSecretInTargetNoteNeverReachesTheReport() throws {
        let run = sampleRun(note: "token=SUPERSECRETVALUE123 for my own notes")
        let markdown = builder.markdown(for: run)
        let json = try builder.json(for: run)

        XCTAssertFalse(markdown.contains("SUPERSECRETVALUE123"), "note leaked into Markdown")
        XCTAssertFalse(json.contains("SUPERSECRETVALUE123"), "note leaked into JSON")
    }

    func testSecretInScenarioNeverReachesTheReport() throws {
        let run = sampleRun(scenario: "Bearer abcdef0123456789abcdefghij")
        XCTAssertFalse(builder.markdown(for: run).contains("abcdef0123456789abcdefghij"))
        XCTAssertFalse(try builder.json(for: run).contains("abcdef0123456789abcdefghij"))
    }

    func testSecretInSystemErrorIsRedacted() throws {
        let run = sampleRun(
            https: HTTPSReport(outcome: .failed,
                               explanation: "failed",
                               systemError: "auth_token=LEAKME123 rejected",
                               errorKind: .tlsCertificateRejected)
        )
        let json = try builder.json(for: run)
        XCTAssertFalse(json.contains("LEAKME123"), "system error leaked into JSON")
    }

    // MARK: - Content

    func testMarkdownIncludesMeasurements() {
        let markdown = builder.markdown(for: sampleRun())
        XCTAssertTrue(markdown.contains("93.184.216.34"))
        XCTAssertTrue(markdown.contains("tls1.3"))
        XCTAssertTrue(markdown.contains("HTTP 200"))
        XCTAssertTrue(markdown.contains("example.com"))
    }

    func testMarkdownMarksFailedStages() {
        let run = sampleRun(
            tls: TLSReport(outcome: .failed,
                           explanation: "The handshake did not complete.",
                           systemError: "tls: handshake failure"),
            https: HTTPSReport.skipped
        )
        let markdown = builder.markdown(for: run)
        XCTAssertTrue(markdown.contains("| TLS | failed |"))
        XCTAssertTrue(markdown.contains("handshake failure"))
    }

    func testSummaryIsHedgedEvenWhenEverythingPasses() {
        // A fully green run must still not read as "everything works".
        let summary = Verdict.summary(for: sampleRun())
        XCTAssertTrue(summary.contains("does not establish"))
    }

    func testEmptyRunSummaryIsHandled() {
        let summary = Verdict.summary(for: DiagnosticRun())
        XCTAssertTrue(summary.contains("No targets"))
    }

    // MARK: - Stability

    func testJSONIsByteIdenticalAcrossRepeatedEncodings() throws {
        let run = sampleRun()
        XCTAssertEqual(try builder.json(for: run), try builder.json(for: run))
    }

    func testPipesInValuesDoNotBreakTheMarkdownTable() {
        let run = sampleRun(
            tls: TLSReport(outcome: .failed,
                           explanation: "bad",
                           systemError: "a|b|c")
        )
        let markdown = builder.markdown(for: run)
        XCTAssertFalse(markdown.contains("| a|b|c |"), "unescaped pipe breaks the table")
        XCTAssertTrue(markdown.contains("a\\|b\\|c"))
    }

    func testReportBundleAlwaysProducesBothFormats() {
        let report = builder.report(for: sampleRun())
        XCTAssertFalse(report.markdown.isEmpty)
        XCTAssertFalse(report.json.isEmpty)
    }
}

final class VerdictTests: XCTestCase {

    func testWorstGradeWins() {
        XCTAssertEqual(Verdict.Grade(worst: .passed, .failed, .passed), .failed)
        XCTAssertEqual(Verdict.Grade(worst: .passed, .passed), .passed)
        XCTAssertEqual(Verdict.Grade(worst: .passed, .skipped), .passed)
        XCTAssertEqual(Verdict.Grade(worst: .skipped, .skipped), .skipped)
    }

    func testEmptyGradeListIsSkipped() {
        XCTAssertEqual(Verdict.Grade(worst:), .skipped)
    }

    func testFailedTLSMakesTheOverallResultFailedEvenIfDNSPassed() {
        let result = TargetResult(
            target: ProbeTarget(label: "x", host: "example.com"),
            dns: DNSReport(outcome: .resolved),
            tls: TLSReport(outcome: .failed),
            https: HTTPSReport.skipped,
            pathAtStart: PathSnapshot()
        )
        XCTAssertEqual(result.overallOutcome, .failed)
    }

    func testEveryGradeHasAnIconAndALocalisedName() {
        for grade in [Verdict.Grade.passed, .failed, .skipped] {
            XCTAssertFalse(grade.symbolName.isEmpty)
            XCTAssertFalse(grade.localizedName.isEmpty)
        }
    }
}

final class PathSnapshotTests: XCTestCase {

    func testSummaryMentionsConstrainedAndExpensiveFlags() {
        let snapshot = PathSnapshot(interface: .cellular, isExpensive: true, isConstrained: true)
        XCTAssertTrue(snapshot.summary.contains("cellular"))
        XCTAssertTrue(snapshot.summary.contains("constrained"))
        XCTAssertTrue(snapshot.summary.contains("expensive"))
    }

    func testSummaryMentionsMissingIPFamilies() {
        let snapshot = PathSnapshot(interface: .wifi, supportsIPv6: false)
        XCTAssertTrue(snapshot.summary.contains("no-ipv6"))
    }

    func testVpnCaveatIsPresentInBothLanguagesAndClaimsNoDetection() {
        DiagnosticsExplainer.withLanguage(.en) {
            XCTAssertTrue(PathSnapshot().vpnCaveat.lowercased().contains("does not report whether a vpn"))
        }
        DiagnosticsExplainer.withLanguage(.ru) {
            XCTAssertTrue(PathSnapshot().vpnCaveat.contains("VPN"))
        }
    }
}