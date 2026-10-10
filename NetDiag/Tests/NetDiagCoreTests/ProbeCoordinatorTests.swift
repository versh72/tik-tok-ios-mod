import XCTest
@testable import NetDiagCore

// MARK: - Fakes

private struct StubDNS: DNSResolving {
    var result: Result<[String], Error>

    func resolve(host: String, timeout: TimeInterval) async throws -> [String] {
        try result.get()
    }
}

private struct StubTLS: TLSProbing {
    var result: Result<TLSHandshake, Error>

    func probe(
        host: String,
        port: UInt16,
        serverName: String,
        timeout: TimeInterval
    ) async throws -> TLSHandshake {
        try result.get()
    }
}

private struct StubHTTPS: HTTPSProbing {
    var result: Result<HTTPSExchange, Error>

    func probe(url: URL, timeout: TimeInterval) async throws -> HTTPSExchange {
        try result.get()
    }
}

// MARK: - Tests

final class ProbeCoordinatorTests: XCTestCase {

    private let path = PathSnapshot(interface: .wifi)

    private func makeCoordinator(
        dns: StubDNS,
        tls: StubTLS,
        https: StubHTTPS
    ) -> ProbeCoordinator {
        ProbeCoordinator(dns: dns, tls: tls, https: https)
    }

    private var happyTarget: ProbeTarget {
        ProbeTarget(label: "Example", host: "example.com")
    }

    // MARK: Happy path

    func testAllStagesPassOnAGoodPath() async {
        let coordinator = makeCoordinator(
            dns: StubDNS(result: .success(["93.184.216.34"])),
            tls: StubTLS(result: .success(TLSHandshake(
                protocolName: "tls1.3",
                cipherSuite: "TLS_AES_128_GCM_SHA256",
                certificateSubject: "example.com",
                milliseconds: 42))),
            https: StubHTTPS(result: .success(HTTPSExchange(
                statusCode: 200, bytesReceived: 0, totalMilliseconds: 80)))
        )

        let result = await coordinator.probe(happyTarget, path: path)

        XCTAssertEqual(result.dns.outcome, .resolved)
        XCTAssertEqual(result.tls.outcome, .established)
        XCTAssertEqual(result.https.outcome, .completed)
        XCTAssertEqual(result.overallOutcome, .passed)
        XCTAssertEqual(result.https.statusCode, 200)
    }

    func testResolvedAddressesAreTruncatedToConfiguredMaximum() async {
        let many = (0..<10).map { "10.0.0.\($0)" }
        let coordinator = ProbeCoordinator(
            dns: StubDNS(result: .success(many)),
            tls: StubTLS(result: .success(TLSHandshake())),
            https: StubHTTPS(result: .success(HTTPSExchange(statusCode: 200))),
            configuration: .init(maxAddressesRecorded: 3)
        )

        let result = await coordinator.probe(happyTarget, path: path)
        XCTAssertEqual(result.dns.addresses.count, 3)
    }

    // MARK: Failure short-circuits

    func testDNSFailureStopsLaterStagesAndIsReportedAsDNS() async {
        // TLS and HTTPS would also fail, but the useful finding is the first
        // cause. Reporting a TLS failure here would send the reader down the
        // wrong path.
        let coordinator = makeCoordinator(
            dns: StubDNS(result: .failure(ProbeError.posix(code: 8, stage: .dns))),
            tls: StubTLS(result: .success(TLSHandshake())),
            https: StubHTTPS(result: .success(HTTPSExchange(statusCode: 200)))
        )

        let result = await coordinator.probe(happyTarget, path: path)

        XCTAssertEqual(result.dns.outcome, .failed)
        XCTAssertEqual(result.tls.outcome, .skipped)
        XCTAssertEqual(result.https.outcome, .skipped)
        XCTAssertEqual(result.overallOutcome, .failed)
    }

    func testTLSFailureStopsHTTPS() async {
        let coordinator = makeCoordinator(
            dns: StubDNS(result: .success(["1.2.3.4"])),
            tls: StubTLS(result: .failure(ProbeError.urlError(
                code: NSURLErrorServerCertificateUntrusted, stage: .tls))),
            https: StubHTTPS(result: .success(HTTPSExchange(statusCode: 200)))
        )

        let result = await coordinator.probe(happyTarget, path: path)

        XCTAssertEqual(result.tls.outcome, .failed)
        XCTAssertEqual(result.https.outcome, .skipped)
    }

    func testHTTPSFailureCarriesABucket() async {
        let coordinator = makeCoordinator(
            dns: StubDNS(result: .success(["1.2.3.4"])),
            tls: StubTLS(result: .success(TLSHandshake())),
            https: StubHTTPS(result: .failure(ProbeError.timedOut(stage: .https)))
        )

        let result = await coordinator.probe(happyTarget, path: path)

        XCTAssertEqual(result.https.outcome, .failed)
        XCTAssertEqual(result.https.errorKind, .connectionTimedOut)
        XCTAssertFalse(result.https.explanation.isEmpty)
    }

    func testEmptyResolutionCountsAsFailure() async {
        // Zero addresses is not a success.
        let coordinator = makeCoordinator(
            dns: StubDNS(result: .success([])),
            tls: StubTLS(result: .success(TLSHandshake())),
            https: StubHTTPS(result: .success(HTTPSExchange(statusCode: 200)))
        )

        let result = await coordinator.probe(happyTarget, path: path)
        XCTAssertEqual(result.dns.outcome, .failed)
        XCTAssertEqual(result.tls.outcome, .skipped)
    }

    // MARK: Robustness

    func testProbeNeverThrowsOnUnknownError() async {
        struct OddError: Error {}

        let coordinator = makeCoordinator(
            dns: StubDNS(result: .failure(OddError())),
            tls: StubTLS(result: .failure(OddError())),
            https: StubHTTPS(result: .failure(OddError()))
        )

        let result = await coordinator.probe(happyTarget, path: path)
        XCTAssertEqual(result.dns.outcome, .failed)
        XCTAssertEqual(result.overallOutcome, .failed)
    }

    func testCertificateExpiryIsSurfacedInTheTLSReport() async {
        let notAfter = Date().addingTimeInterval(-3_600)
        let coordinator = makeCoordinator(
            dns: StubDNS(result: .success(["1.2.3.4"])),
            tls: StubTLS(result: .success(TLSHandshake(
                certificateSubject: "example.com",
                certificateNotAfter: notAfter,
                milliseconds: 10))),
            https: StubHTTPS(result: .success(HTTPSExchange(statusCode: 200)))
        )

        let result = await coordinator.probe(happyTarget, path: path)

        let expires = try XCTUnwrap(result.tls.certificateExpiresInSeconds)
        XCTAssertLessThan(expires, 0, "an expired certificate must read as negative remaining time")
    }

    func testScenarioIsCarriedOntoTheTarget() async {
        let target = ProbeTarget(label: "x", host: "example.com", scenario: "VPN on")
        let coordinator = makeCoordinator(
            dns: StubDNS(result: .success(["1.2.3.4"])),
            tls: StubTLS(result: .success(TLSHandshake())),
            https: StubHTTPS(result: .success(HTTPSExchange(statusCode: 200)))
        )
        let result = await coordinator.probe(target, path: path)
        XCTAssertEqual(result.target.scenario, "VPN on")
    }
}