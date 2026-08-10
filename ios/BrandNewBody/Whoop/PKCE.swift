import Foundation
import CryptoKit

/// RFC 7636. The verifier is a random string only this device ever holds;
/// the challenge — its SHA-256, base64url-encoded — is what WHOOP sees during
/// authorization.
///
/// This is what actually closes the risk a private-use URL scheme carries:
/// RFC 8252 notes that more than one app on a device can register the same
/// scheme, so the OS has no way to guarantee WHOOP's redirect reaches THIS
/// app rather than an impostor that happened to claim the same one. Without
/// PKCE, whoever received that redirect would hold a usable authorization
/// code. With it, they hold a code that is worthless without the verifier —
/// which never left this device and never travels in the redirect at all.
struct PKCE {
    let verifier: String
    let challenge: String

    static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        // SecRandomCopyBytes failing at all means the platform's CSPRNG is
        // unavailable — not a recoverable condition, and continuing with a
        // predictable verifier would defeat the entire point of this type.
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        let verifier = Data(bytes).base64URLEncoded()
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncoded()
        return PKCE(verifier: verifier, challenge: challenge)
    }
}

private extension Data {
    /// RFC 4648 §5 — the same alphabet base64url encoding always uses, with
    /// padding stripped, which is what both PKCE and WHOOP's token endpoint
    /// expect.
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
