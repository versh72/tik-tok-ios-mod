import XCTest
@testable import NetDiagCore

final class FailureClassifierTests: XCTestCase {

    private let classifier = FailureClassifier()

    // MARK: - POSIX

    func testPosixTimeoutIsClassified() {
        XCTAssertEqual(
            classifier.classify(posixError: POSIXErrorCode.ETIMEDOUT.rawValue),
            .connectionTimedOut
        )
    }

    func testPosixRefusedIsClassified() {
        XCTAssertEqual(
            classifier.classify(posixError: POSIXErrorCode.ECONNREFUSED.rawValue),
            .connectionRefused
        )
    }

    func testPosixResetIsClassified() {
        XCTAssertEqual(
            classifier.classify(posixError: POSIXErrorCode.ECONNRESET.rawValue),
            .connectionLost
        )
    }

    func testPosixUnreachableIsClassifiedAsNoPath() {
        XCTAssertEqual(
            classifier.classify(posixError: POSIXErrorCode.ENETUNREACH.rawValue),
            .notConnected
        )
        XCTAssertEqual(
            classifier.classify(posixError: POSIXErrorCode.EHOSTUNREACH.rawValue),
            .notConnected
        )
    }

    func testUnknownPosixCodeIsNotGuessed() {
        // A code the table does not name must not be assigned a specific
        // bucket on a hunch.
        XCTAssertEqual(classifier.classify(posixError: 12_345), .unknown)
    }

    // MARK: - URLError

    func testCannotFindHostIsDNSFailure() {
        XCTAssertEqual(
            classifier.classify(urlErrorCode: NSURLErrorCannotFindHost),
            .dnsResolutionFailed
        )
        XCTAssertEqual(
            classifier.classify(urlErrorCode: NSURLErrorDNSLookupFailed),
            .dnsResolutionFailed
        )
    }

    func testBadCertificateDateIsExpiryNotGenericRejection() {
        // "Expired" and "untrusted root" lead to different actions, so they
        // must not collapse into one bucket.
        XCTAssertEqual(
            classifier.classify(urlErrorCode: NSURLErrorServerCertificateHasBadDate),
            .tlsCertificateExpired
        )
        XCTAssertEqual(
            classifier.classify(urlErrorCode: NSURLErrorServerCertificateUntrusted),
            .tlsCertificateRejected
        )
    }

    func testSecureConnectionFailureIsHandshakeFailure() {
        XCTAssertEqual(
            classifier.classify(urlErrorCode: NSURLErrorSecureConnectionFailed),
            .tlsHandshakeFailed
        )
    }

    func testTimedOutURLCodeIsClassified() {
        XCTAssertEqual(
            classifier.classify(urlErrorCode: NSURLErrorTimedOut),
            .connectionTimedOut
        )
    }

    func testCancellationIsClassified() {
        XCTAssertEqual(classifier.classify(urlErrorCode: NSURLErrorCancelled), .cancelled)
    }

    func testUnrecognisedURLCodeIsNotGuessed() {
        XCTAssertEqual(classifier.classify(urlErrorCode: -99_999), .unknown)
    }

    func testTypedURLErrorIsClassified() {
        let error = URLError(.cannotFindHost)
        XCTAssertEqual(classifier.classify(urlError: error), .dnsResolutionFailed)
    }

    // MARK: - Free text

    func testExpiredCertificateTextIsDetected() {
        XCTAssertEqual(
            classifier.classify(description: "The certificate has expired"),
            .tlsCertificateExpired
        )
    }

    func testTimeoutTextIsDetected() {
        XCTAssertEqual(
            classifier.classify(description: "Request timed out"),
            .connectionTimedOut
        )
    }

    func testUnrecognisedTextYieldsUnknown() {
        XCTAssertEqual(classifier.classify(description: "something odd"), .unknown)
    }

    func testEmptyTextYieldsUnknown() {
        XCTAssertEqual(classifier.classify(description: ""), .unknown)
    }

    // MARK: - ProbeError mapping

    func testProbeErrorPosixCarriesStage() {
        let error = ProbeError.posix(code: POSIXErrorCode.ETIMEDOUT.rawValue, stage: .tls)
        XCTAssertEqual(error.stage, .tls)
        XCTAssertEqual(error.failureKind(using: classifier), .connectionTimedOut)
        XCTAssertTrue(error.rawDescription.contains("TLS"), error.rawDescription)
    }

    func testProbeErrorTimeoutAlwaysMapsToTimeout() {
        let error = ProbeError.timedOut(stage: .dns)
        XCTAssertEqual(error.failureKind(using: classifier), .connectionTimedOut)
        XCTAssertTrue(error.rawDescription.contains("dns"))
    }

    // MARK: - Explanations

    func testEveryBucketHasANonEmptyExplanation() {
        for kind in FailureKind.allCases {
            let text = classifier.explain(kind)
            XCTAssertFalse(text.isEmpty, "no explanation for \(kind.identifier)")
        }
    }

    func testExplanationsDoNotNameAnyApplication() {
        // The tool measures a path. It must not assert anything about what a
        // particular app does.
        let forbidden = ["tiktok", "douyin", "musically"]
        for kind in FailureKind.allCases {
            let lower = classifier.explain(kind).lowercased()
            for word in forbidden {
                XCTAssertFalse(lower.contains(word),
                               "explanation for \(kind.identifier) names an application")
            }
        }
    }

    func testExplanationFollowsSelectedLanguage() {
        DiagnosticsExplainer.withLanguage(.ru) {
            XCTAssertTrue(classifier.explain(.connectionTimedOut).contains("таймаут")
                          || classifier.explain(.connectionTimedOut).contains("Ответ"))
        }
        DiagnosticsExplainer.withLanguage(.en) {
            XCTAssertTrue(classifier.explain(.connectionTimedOut).contains("deadline"))
        }
    }
}