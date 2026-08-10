import XCTest
import CryptoKit
@testable import BrandNewBody

/// Everything here is deliberately network-free: PKCE math, date matching,
/// and the one configuration invariant that would otherwise fail silently —
/// getting these right in a unit test is a lot cheaper than getting them
/// wrong on a device mid-OAuth-flow.
final class WhoopTests: XCTestCase {

    // MARK: - WhoopConfig

    /// `redirectURI` and `redirectScheme` are two properties naming the same
    /// scheme; nothing enforces they agree except this test. If they drift,
    /// WHOOP's redirect still fires, `ASWebAuthenticationSession` (armed
    /// with the stale scheme) simply never catches it, and the flow hangs
    /// with no error to point at either value.
    func testRedirectURIUsesTheDeclaredScheme() {
        XCTAssertTrue(WhoopConfig.redirectURI.hasPrefix("\(WhoopConfig.redirectScheme)://"))
    }

    func testUnconfiguredPlaceholdersAreDetected() {
        XCTAssertFalse(WhoopConfig.isConfigured)
    }

    // MARK: - PKCE

    func testChallengeIsTheVerifiersSHA256() {
        let pkce = PKCE.generate()
        let expected = base64URL(Data(SHA256.hash(data: Data(pkce.verifier.utf8))))
        XCTAssertEqual(pkce.challenge, expected)
    }

    func testEveryGenerateCallIsFresh() {
        let a = PKCE.generate()
        let b = PKCE.generate()
        XCTAssertNotEqual(a.verifier, b.verifier)
        XCTAssertNotEqual(a.challenge, b.challenge)
    }

    /// PKCE forbids `+`, `/` and `=` in both values — WHOOP's token endpoint
    /// receives these over a URL-encoded form body, where an unescaped `+`
    /// silently becomes a space.
    func testValuesAreBase64URLNotPlainBase64() {
        let pkce = PKCE.generate()
        for value in [pkce.verifier, pkce.challenge] {
            XCTAssertFalse(value.contains("+"))
            XCTAssertFalse(value.contains("/"))
            XCTAssertFalse(value.contains("="))
        }
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - WhoopDay

    func testSameDayMatchesRegardlessOfFractionalSeconds() {
        XCTAssertTrue(WhoopDay.isSameDay("2026-08-06T10:15:00.000Z", as: "2026-08-06"))
        XCTAssertTrue(WhoopDay.isSameDay("2026-08-06T10:15:00Z", as: "2026-08-06"))
    }

    func testDifferentDayDoesNotMatch() {
        XCTAssertFalse(WhoopDay.isSameDay("2026-08-05T23:59:00Z", as: "2026-08-06"))
    }

    func testNilOrMalformedTimestampDoesNotMatch() {
        XCTAssertFalse(WhoopDay.isSameDay(nil, as: "2026-08-06"))
        XCTAssertFalse(WhoopDay.isSameDay("not a timestamp", as: "2026-08-06"))
    }
}
