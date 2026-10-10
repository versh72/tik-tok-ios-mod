import XCTest
@testable import NetDiagCore

final class EndpointValidatorTests: XCTestCase {

    // MARK: - Host

    func testPlainHostnameIsAccepted() throws {
        XCTAssertEqual(try EndpointValidator.validateHost("example.com"), "example.com")
    }

    func testSurroundingWhitespaceIsTrimmed() throws {
        XCTAssertEqual(try EndpointValidator.validateHost("  example.com \n"), "example.com")
    }

    func testEmptyHostIsRejected() {
        XCTAssertThrowsError(try EndpointValidator.validateHost("   ")) { error in
            XCTAssertEqual(error as? EndpointValidator.ValidationError, .emptyHost)
        }
    }

    func testOverlongHostIsRejected() {
        let long = String(repeating: "a", count: 300)
        XCTAssertThrowsError(try EndpointValidator.validateHost(long)) { error in
            XCTAssertEqual(error as? EndpointValidator.ValidationError, .hostTooLong)
        }
    }

    func testHostWithPathIsRejected() {
        // A host field must not be able to smuggle a path.
        XCTAssertThrowsError(try EndpointValidator.validateHost("example.com/secret"))
    }

    func testHostWithAtSignIsRejected() {
        XCTAssertThrowsError(try EndpointValidator.validateHost("user@example.com"))
    }

    func testHostWithPortInHostFieldIsRejected() {
        XCTAssertThrowsError(try EndpointValidator.validateHost("example.com:8080"))
    }

    func testHostWithQueryIsRejected() {
        XCTAssertThrowsError(try EndpointValidator.validateHost("example.com?a=1"))
    }

    func testEmptyDNSLabelIsRejected() {
        XCTAssertThrowsError(try EndpointValidator.validateHost("example..com"))
    }

    func testLeadingHyphenLabelIsRejected() {
        XCTAssertThrowsError(try EndpointValidator.validateHost("-bad.example.com"))
    }

    func testIPv4LiteralIsAccepted() throws {
        XCTAssertEqual(try EndpointValidator.validateHost("192.168.1.1"), "192.168.1.1")
    }

    func testBracketedIPv6LiteralIsAccepted() throws {
        XCTAssertEqual(try EndpointValidator.validateHost("[2001:db8::1]"), "[2001:db8::1]")
    }

    // MARK: - Path

    func testEmptyPathBecomesRoot() throws {
        XCTAssertEqual(try EndpointValidator.validatePath(""), "/")
    }

    func testRelativePathIsRejected() {
        XCTAssertThrowsError(try EndpointValidator.validatePath("health"))
    }

    func testPathWithSpaceIsRejected() {
        XCTAssertThrowsError(try EndpointValidator.validatePath("/a b"))
    }

    func testNestedPathIsAccepted() throws {
        XCTAssertEqual(try EndpointValidator.validatePath("/a/b/c"), "/a/b/c")
    }

    // MARK: - Port

    func testValidPortIsAccepted() throws {
        XCTAssertEqual(try EndpointValidator.validatePort(8443), 8443)
    }

    func testZeroPortIsRejected() {
        XCTAssertThrowsError(try EndpointValidator.validatePort(0)) { error in
            XCTAssertEqual(error as? EndpointValidator.ValidationError, .invalidPort)
        }
    }

    func testPortAboveRangeIsRejected() {
        XCTAssertThrowsError(try EndpointValidator.validatePort(70_000))
    }

    // MARK: - Full target parsing

    func testBareHostBecomesTarget() throws {
        let target = try EndpointValidator.makeTarget(label: "Test", input: "example.com")
        XCTAssertEqual(target.host, "example.com")
        XCTAssertEqual(target.port, 443)
        XCTAssertEqual(target.path, "/")
        XCTAssertEqual(target.label, "Test")
    }

    func testHostWithPortIsParsed() throws {
        let target = try EndpointValidator.makeTarget(label: "", input: "example.com:8443")
        XCTAssertEqual(target.host, "example.com")
        XCTAssertEqual(target.port, 8443)
    }

    func testFullURLIsParsed() throws {
        let target = try EndpointValidator.makeTarget(
            label: "Full",
            input: "https://example.com:9443/health/ready"
        )
        XCTAssertEqual(target.host, "example.com")
        XCTAssertEqual(target.port, 9443)
        XCTAssertEqual(target.path, "/health/ready")
    }

    func testQueryStringIsDiscardedAtParseTime() throws {
        // The single most important case: a pasted signed URL must never
        // reach the probe, the log or the report.
        let target = try EndpointValidator.makeTarget(
            label: "Signed",
            input: "https://example.com/feed?access_token=SECRETTOKEN&x=1"
        )
        XCTAssertEqual(target.path, "/feed")
        XCTAssertFalse(target.path.contains("SECRETTOKEN"))
    }

    func testHTTPIsRejectedSoProbesCannotDowngrade() {
        XCTAssertThrowsError(
            try EndpointValidator.makeTarget(label: "", input: "http://example.com")
        ) { error in
            guard case .schemeNotAllowed(let scheme)? =
                    error as? EndpointValidator.ValidationError else {
                return XCTFail("expected schemeNotAllowed, got \(error)")
            }
            XCTAssertEqual(scheme, "http")
        }
    }

    func testNonHTTPSchemeIsRejected() {
        XCTAssertThrowsError(
            try EndpointValidator.makeTarget(label: "", input: "ftp://example.com")
        )
    }

    func testEmptyLabelFallsBackToHost() throws {
        let target = try EndpointValidator.makeTarget(label: "   ", input: "example.com")
        XCTAssertEqual(target.label, "example.com")
    }

    func testOverlongLabelIsRejected() {
        let label = String(repeating: "x", count: 100)
        XCTAssertThrowsError(
            try EndpointValidator.makeTarget(label: label, input: "example.com")
        ) { error in
            XCTAssertEqual(error as? EndpointValidator.ValidationError, .labelTooLong)
        }
    }

    // MARK: - URL construction

    func testDefaultPortIsOmittedFromURL() throws {
        let target = try EndpointValidator.makeTarget(label: "", input: "example.com")
        XCTAssertEqual(target.url?.absoluteString, "https://example.com/")
    }

    func testNonDefaultPortIsIncludedInURL() throws {
        let target = try EndpointValidator.makeTarget(label: "", input: "example.com:8443")
        XCTAssertEqual(target.url?.absoluteString, "https://example.com:8443/")
    }

    func testAuthorityOmitsDefaultPort() throws {
        let target = try EndpointValidator.makeTarget(label: "", input: "example.com")
        XCTAssertEqual(target.authority, "example.com")

        let other = try EndpointValidator.makeTarget(label: "", input: "example.com:8443")
        XCTAssertEqual(other.authority, "example.com:8443")
    }
}