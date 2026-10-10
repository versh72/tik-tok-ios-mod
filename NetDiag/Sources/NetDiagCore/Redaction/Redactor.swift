import Foundation

/// Removes anything that could carry a secret or personal data from a string
/// before it is written to a log or an export.
///
/// The tool never reads cookies, tokens or request payloads in the first
/// place, so this is a second line of defence rather than the primary one.
/// It exists because the person typing a probe target can paste a URL that
/// still contains a signed query string, and because free-text notes and
/// labels are user input.
public enum Redactor {

    public enum Policy: String, Codable, Sendable {
        /// Replace the whole sensitive run with a fixed marker.
        case mask
        /// Keep a short prefix so different values stay distinguishable.
        case truncate
    }

    /// Marker written in place of a removed value.
    public static let mask = "[redacted]"

    // MARK: - Query strings

    /// Parameter names whose values are dropped from any recorded URL.
    ///
    /// Matching is case-insensitive on the name and substring-based, because
    /// the same secret is spelled differently across services.
    public static let sensitiveQueryNames: Set<String> = [
        "access_token", "accesstoken", "api_key", "apikey", "auth", "auth_key",
        "auth_token", "authorization", "code", "credential", "credentials",
        "device_id", "deviceid", "id_token", "id_token_hinter",
        "install_id", "installid", "key", "nonce", "openid", "password",
        "passwd", "pwd", "refresh_token", "refreshtoken", "secret",
        "session", "session_id", "sessionid", "sig", "signature", "sign",
        "ssid", "ticket", "token", "user_id", "userid", "uuid"
    ]

    /// Rewrites a URL so that sensitive query values are removed.
    ///
    /// The scheme, host, port and path are preserved: they are the part of the
    /// result that makes a diagnostic report useful. Only query values are
    /// touched.
    public static func redact(urlString: String, policy: Policy = .truncate) -> String {
        guard var components = URLComponents(string: urlString) else {
            // Not parseable as a URL. Treat the whole thing as untrusted input
            // and keep only the leading host-like token.
            return redactFreeText(urlString)
        }

        if let items = components.queryItems, !items.isEmpty {
            // A plain counter, not Set.hashValue: Swift seeds its hasher per
            // process, and an export has to be reproducible across launches.
            var occurrence = 0
            components.queryItems = items.map { item in
                let name = item.name.lowercased()
                guard sensitiveQueryNames.contains(name)
                        || name.contains("token")
                        || name.contains("secret")
                        || name.contains("password")
                        || name.contains("sign")
                else { return item }

                occurrence += 1
                return URLQueryItem(
                    name: item.name,
                    value: policy == .mask ? mask : maskSuffix(item.value, seed: occurrence)
                )
            }
        }

        // Userinfo in the URL (user:password@host) is always secret.
        if components.user != nil || components.password != nil {
            components.user = mask
            components.password = nil
        }

        return components.string ?? mask
    }

    /// Produces a stable, non-reversible suffix so two runs can be told apart
    /// without either value being recoverable.
    private static func maskSuffix(_ value: String?, seed: Int) -> String {
        guard let value, !value.isEmpty else { return mask }
        let digest = stableHash(value + String(seed))
        return "\(mask)#\(digest.prefix(8))"
    }

    /// FNV-1a 64-bit. Small, dependency-free and, importantly, not a
    /// cryptographic hash: it is used only to tell values apart, never to
    /// protect them. Nothing secret is ever protected by this.
    private static func stableHash(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 16)
    }

    // MARK: - Free text

    /// Patterns replaced in any free-text field (labels, notes, error strings).
    static let freeTextPatterns: [(pattern: String, replacement: String)] = [
        // Bearer / Basic / token headers pasted into a note.
        ("(?i)\\b(bearer|basic)\\s+[A-Za-z0-9._~+/=-]{8,}", "$1 " + mask),
        // key=value / key: value pairs for sensitive names.
        ("(?i)\\b(access[_-]?token|refresh[_-]?token|api[_-]?key|apikey|secret|password|passwd|pwd|session[_-]?id|sid|signature|sig)\\b\\s*[:=]\\s*[^\\s,;\"')\\]]+", "$1=" + mask),
        // e-mail addresses.
        ("(?i)\\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}\\b", mask),
        // Long opaque blobs that look like tokens or keys.
        ("\\b[A-Za-z0-9_-]{40,}\\b", mask)
    ]

    /// Applies every free-text pattern. Exposed for testing.
    public static func redactFreeText(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var result = text
        for rule in freeTextPatterns {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: rule.replacement
            )
        }
        return result
    }

    /// Redacts a URL if it looks like one, otherwise redacts it as free text.
    public static func redact(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("://") {
            return redact(urlString: trimmed)
        }
        return redactFreeText(trimmed)
    }

    /// Clipboard-shaped helper for a whole dictionary of user input.
    public static func redactAll(_ values: [String: String]) -> [String: String] {
        values.mapValues(redact)
    }
}