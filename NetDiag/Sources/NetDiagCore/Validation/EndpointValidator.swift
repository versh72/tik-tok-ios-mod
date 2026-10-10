import Foundation

/// Validates and normalises what the person running the tool typed in.
///
/// Rejecting bad input here, rather than at connect time, is what keeps the
/// probes honest: a target that the tool refuses to accept produces a clear
/// message instead of an ambiguous network error ten seconds later.
public enum EndpointValidator {

    public enum ValidationError: Error, Equatable, Sendable {
        case emptyHost
        case hostTooLong
        case invalidCharacters(String)
        case invalidPort
        case schemeNotAllowed(String)
        case pathNotAllowed
        case labelTooLong

        public var message: String {
            DiagnosticsExplainer.text(
                en: "Invalid target: \(english). Fix the field and try again.",
                ru: "Некорректная цель: \(russian). Исправьте поле и повторите.")
        }

        var english: String {
            switch self {
            case .emptyHost:            return "the host is empty"
            case .hostTooLong:          return "the host is longer than 253 characters"
            case .invalidCharacters(let c): return "the host contains an illegal character (\(c))"
            case .invalidPort:          return "the port must be between 1 and 65535"
            case .schemeNotAllowed(let s): return "only https is accepted, but the scheme was \(s)"
            case .pathNotAllowed:        return "the path must start with / and contain no whitespace"
            case .labelTooLong:         return "the label is longer than 64 characters"
            }
        }

        var russian: String {
            switch self {
            case .emptyHost:            return "хост пуст"
            case .hostTooLong:          return "хост длиннее 253 символов"
            case .invalidCharacters(let c): return "хост содержит недопустимый символ (\(c))"
            case .invalidPort:          return "порт должен быть в диапазоне 1…65535"
            case .schemeNotAllowed(let s): return "принимается только https, а схема была \(s)"
            case .pathNotAllowed:        return "путь должен начинаться с / и не содержать пробелов"
            case .labelTooLong:         return "подпись длиннее 64 символов"
            }
        }
    }

    /// Longest legal DNS name.
    public static let maxHostLength = 253
    /// Longest label accepted for the human-readable name.
    public static let maxLabelLength = 64

    /// Accepts a host that is a DNS name, or an IPv4/IPv6 literal.
    ///
    /// Only characters that can legally appear in those forms are allowed.
    /// This is deliberately stricter than `URLComponents`: it rejects a host
    /// that would smuggle a path, userinfo or port into the field.
    public static func validateHost(_ raw: String) throws -> String {
        let host = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { throw ValidationError.emptyHost }
        guard host.count <= maxHostLength else { throw ValidationError.hostTooLong }

        // IPv6 literal, optionally bracketed.
        if host.hasPrefix("["), host.hasSuffix("]") {
            let inner = String(host.dropFirst().dropLast())
            guard inner.allSatisfy({ $0.isHexDigit || $0 == ":" || $0 == "." }),
                  inner.contains(":")
            else { throw ValidationError.invalidCharacters(host) }
            return "[\(inner)]"
        }

        // Reject anything with characters that cannot appear in a DNS name or
        // IPv4 literal: in particular '/', '@', '?', '#', whitespace, ':'.
        let illegal = host.first { character in
            !(character.isLetter && character.isASCII)
                && !(character.isNumber && character.isASCII)
                && character != "-"
                && character != "."
                && character != "_"
        }
        if let illegal {
            throw ValidationError.invalidCharacters(String(illegal))
        }

        // A bare ':' would mean a port was typed into the host field.
        if host.contains(":") {
            guard let first = host.first, first.isHexDigit || first.isNumber,
                  host.filter({ $0 == ":" }).count >= 2
            else { throw ValidationError.invalidCharacters(":") }
            // Looks like a bare IPv6 literal.
            return host
        }

        // Labels: no empty labels, no leading/trailing hyphen.
        for label in host.split(separator: ".", omittingEmptySubsequences: false) {
            guard !label.isEmpty else { throw ValidationError.invalidCharacters(".") }
            if label.hasPrefix("-") || label.hasSuffix("-") {
                throw ValidationError.invalidCharacters("-")
            }
        }

        return host
    }

    /// Normalises a path. Returns "/" for empty input.
    public static func validatePath(_ raw: String) throws -> String {
        let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return "/" }
        guard path.hasPrefix("/") else { throw ValidationError.pathNotAllowed }
        guard !path.contains(where: { $0.isWhitespace }) else {
            throw ValidationError.pathNotAllowed
        }
        return path
    }

    /// Port range check.
    public static func validatePort(_ port: Int) throws -> UInt16 {
        guard (1...65535).contains(port) else { throw ValidationError.invalidPort }
        return UInt16(port)
    }

    /// Turns whatever the user typed into a `ProbeTarget`.
    ///
    /// Accepts a bare host, `host:port`, or a full `https://…` URL. Any other
    /// scheme is refused, so an `http://` target cannot silently downgrade a
    /// probe to cleartext.
    public static func makeTarget(
        label rawLabel: String,
        input rawInput: String,
        scenario: String = "",
        note: String = ""
    ) throws -> ProbeTarget {

        var input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { throw ValidationError.emptyHost }

        var port = 443
        var path = "/"

        if let schemeRange = input.range(of: "://") {
            let scheme = String(input[input.startIndex..<schemeRange.lowerBound]).lowercased()
            guard scheme == "https" else {
                throw ValidationError.schemeNotAllowed(scheme)
            }
            input = String(input[schemeRange.upperBound...])

            if let slash = input.firstIndex(of: "/") {
                path = String(input[slash...])
                input = String(input[input.startIndex..<slash])
            }
            if let questionMark = path.firstIndex(of: "?") {
                // The query string is never used for probing and is not
                // recorded. Drop it here so it can never reach the log.
                path = String(path[path.startIndex..<questionMark])
            }
        }

        // Split a trailing :port, but leave a bare IPv6 literal alone.
        if let colon = input.lastIndex(of: ":"), !input.contains("::") {
            let maybePort = String(input[input.index(after: colon)...])
            if let parsed = Int(maybePort), input[input.startIndex..<colon].contains(":") == false {
                port = parsed
                input = String(input[input.startIndex..<colon])
            }
        }

        let host = try validateHost(input)
        port = try validatePort(port)
        path = try validatePath(path)

        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard label.count <= maxLabelLength else { throw ValidationError.labelTooLong }

        return ProbeTarget(
            label: label.isEmpty ? host : label,
            host: host,
            port: port,
            path: path,
            scenario: scenario,
            note: note
        )
    }
}