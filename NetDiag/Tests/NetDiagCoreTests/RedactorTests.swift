import XCTest
@testable import NetDiagCore

final class RedactorTests: XCTestCase {

    // MARK: - Query strings

    func testSensitiveQueryValuesAreRemoved() {
        let input = "https://example.com/path?access_token=abcdef123456&page=2"
        let output = Redactor.redact(urlString: input)

        XCTAssertFalse(output.contains("abcdef123456"), "token leaked into \(output)")
        XCTAssertTrue(output.contains("access_token="), "query key was dropped entirely")
        XCTAssertTrue(output.contains("page=2"), "a harmless parameter must survive")
        XCTAssertTrue(output.contains("example.com"), "host must survive")
        XCTAssertTrue(output.contains("/path"), "path must survive")
    }

    func testSubstringMatchingCatchesUnlistedTokenNames() {
        let input = "https://example.com/?x_rt_refreshToken=zzz"
        let output = Redactor.redact(urlString: input)
        XCTAssertFalse(output.contains("zzz"))
    }

    func testMaskPolicyReplacesWithFixedMarker() {
        let input = "https://example.com/?sig=SECRETSIG"
        let output = Redactor.redact(urlString: input, policy: .mask)
        XCTAssertTrue(output.contains("sig=\(Redactor.mask)"))
        XCTAssertFalse(output.contains("SECRETSIG"))
    }

    func testTruncatePolicyIsStableAcrossCalls() {
        let input = "https://example.com/?token=repeatable-value"
        let first = Redactor.redact(urlString: input)
        let second = Redactor.redact(urlString: input)
        XCTAssertEqual(first, second, "redaction must be reproducible across calls")
    }

    func testTwoDifferentTokensGetDifferentMarkers() {
        let a = Redactor.redact(urlString: "https://example.com/?token=alpha")
        let b = Redactor.redact(urlString: "https://example.com/?token=beta")
        XCTAssertNotEqual(a, b, "distinct values must stay distinguishable without revealing either")
    }

    func testURLUserInfoIsRemoved() {
        let input = "https://user:hunter2@example.com/"
        let output = Redactor.redact(urlString: input)
        XCTAssertFalse(output.contains("hunter2"), "password leaked into \(output)")
    }

    func testNonURLInputFallsBackToFreeText() {
        let output = Redactor.redact(urlString: "contact me at a.person@example.com")
        XCTAssertFalse(output.contains("a.person@example.com"))
    }

    // MARK: - Free text

    func testBearerTokenInFreeTextIsRemoved() {
        let output = Redactor.redactFreeText("failed with Bearer abcdef0123456789abcdef")
        XCTAssertFalse(output.contains("abcdef0123456789abcdef"), "bearer leaked into \(output)")
        XCTAssertTrue(output.lowercased().contains("bearer"))
    }

    func testEmailInFreeTextIsRemoved() {
        let output = Redactor.redactFreeText("write to john.doe@example.org please")
        XCTAssertFalse(output.contains("john.doe@example.org"))
        XCTAssertTrue(output.contains("please"), "surrounding text must survive")
    }

    func testKeyValueSecretInFreeTextIsRemoved() {
        let output = Redactor.redactFreeText("password=hunter2 remaining")
        XCTAssertFalse(output.contains("hunter2"))
        XCTAssertTrue(output.contains("remaining"))
    }

    func testLongOpaqueBlobIsRemoved() {
        let blob = String(repeating: "A1b2C3d4", count: 8)   // 64 chars
        let output = Redactor.redactFreeText("value=\(blob)")
        XCTAssertFalse(output.contains(blob), "opaque blob leaked into \(output)")
    }

    func testOrdinarySentenceIsUntouched() {
        let text = "The DNS lookup returned two addresses in 34 ms."
        XCTAssertEqual(Redactor.redactFreeText(text), text)
    }

    func testEmptyInputIsHandled() {
        XCTAssertEqual(Redactor.redactFreeText(""), "")
    }

    // MARK: - Dispatch

    func testRedactChoosesURLPathWhenSchemeIsPresent() throws {
        let output = Redactor.redact("https://example.com/?token=abc")
        XCTAssertFalse(output.contains("abc"))
    }

    func testRedactDictionaryAppliesToEveryValue() {
        let output = Redactor.redactAll([
            "a": "token=abcdefghijklmnop",
            "b": "nothing sensitive here"
        ])
        XCTAssertFalse(output["a"]!.contains("abcdefghijklmnop"))
        XCTAssertEqual(output["b"], "nothing sensitive here")
    }
}