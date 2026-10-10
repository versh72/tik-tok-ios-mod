import Foundation

/// The symbolic bucket a failure falls into.
///
/// Buckets exist so that results can be compared across runs and across
/// network configurations without comparing raw error strings.
public enum FailureKind: String, Hashable, Codable, CaseIterable, Sendable {
    case dnsResolutionFailed
    case dnsBlocked
    case tlsHandshakeFailed
    case tlsCertificateRejected
    case tlsCertificateExpired
    case connectionTimedOut
    case connectionRefused
    case connectionLost
    case notConnected
    case httpError
    case tooManyRedirects
    case cancelled
    case unknown

    /// Stable, non-localised key. Used in exported JSON and in tests.
    public var identifier: String { rawValue }
}

/// Classifies raw system error values into a `FailureKind`.
///
/// Kept free of UIKit, Network framework and localisation so that it can be
/// unit-tested with plain values.
///
/// POSIX classification compares against `POSIXErrorCode` raw values rather
/// than hand-written integers, so the mapping stays correct on every platform
/// without this file having to know Darwin's errno numbering. Anything the
/// table does not name maps to `.unknown` on purpose: guessing a more
/// specific bucket from an unrecognised code would be a false claim.
public struct FailureClassifier: Sendable {

    public init() {}

    // MARK: - POSIX

    /// Classifies an `errno` value returned from a BSD socket call or
    /// `getaddrinfo`.
    public func classify(posixError code: Int32) -> FailureKind {
        switch POSIXErrorCode(rawValue: code) {
        case .some(let value):
            return classify(posixError: value)
        case .none:
            return .unknown
        }
    }

    /// Classifies a typed `POSIXErrorCode`.
    public func classify(posixError code: POSIXErrorCode) -> FailureKind {
        switch code {
        case .ENETDOWN, .ENETUNREACH, .EHOSTDOWN, .EHOSTUNREACH, .ENOTCONN,
             .EADDRNOTAVAIL, .EPERM:
            return .notConnected

        case .ECONNABORTED, .ECONNRESET, .EPIPE, .ENETRESET:
            return .connectionLost

        case .ETIMEDOUT:
            return .connectionTimedOut

        case .ECONNREFUSED:
            return .connectionRefused

        case .EPROTO, .EPROTONOSUPPORT, .ESOCKTNOSUPPORT, .EOPNOTSUPP:
            return .tlsHandshakeFailed

        case .ENOENT:
            return .dnsResolutionFailed

        default:
            return .unknown
        }
    }

    // MARK: - URLError / NSURLErrorDomain

    /// Classifies a `URLError` code.
    public func classify(urlErrorCode code: Int) -> FailureKind {
        // NSURLError* constants are the raw values of URLError.Code.
        switch code {
        case NSURLErrorCancelled:
            return .cancelled
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed:
            return .dnsResolutionFailed
        case NSURLErrorTimedOut, NSURLErrorCannotConnectToHost:
            return .connectionTimedOut
        case NSURLErrorNetworkConnectionLost:
            return .connectionLost
        case NSURLErrorNotConnectedToInternet, NSURLErrorCannotConnect:
            return .notConnected
        case NSURLErrorSecureConnectionFailed:
            return .tlsHandshakeFailed
        case NSURLErrorServerCertificateHasBadDate:
            return .tlsCertificateExpired
        case NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid,
             NSURLErrorClientCertificateRejected,
             NSURLErrorClientCertificateRequired:
            return .tlsCertificateRejected
        case NSURLErrorHTTPTooManyRedirects:
            return .tooManyRedirects
        case NSURLErrorBadServerResponse:
            return .httpError
        default:
            return .unknown
        }
    }

    /// Classifies a typed `URLError`.
    public func classify(urlError error: URLError) -> FailureKind {
        classify(urlErrorCode: error.errorCode)
    }

    // MARK: - Arbitrary descriptions

    /// Best-effort bucket for a free-form error string, used when no typed
    /// error object is available. Never claims more precision than the text
    /// supports: unrecognised input yields `.unknown`.
    public func classify(description: String) -> FailureKind {
        let text = description.lowercased()
        guard !text.isEmpty else { return .unknown }

        if text.contains("certificate has expired") || text.contains("cert_expired") {
            return .tlsCertificateExpired
        }
        if text.contains("certificate") || text.contains("trust")
            || (text.contains("ssl") && text.contains("fail")) {
            return .tlsCertificateRejected
        }
        if text.contains("handshake") || text.contains("tls") || text.contains("secure connection") {
            return .tlsHandshakeFailed
        }
        if text.contains("timed out") || text.contains("timeout") {
            return .connectionTimedOut
        }
        if text.contains("refused") {
            return .connectionRefused
        }
        if text.contains("not connected") || text.contains("offline") || text.contains("unreachable") {
            return .notConnected
        }
        if text.contains("resolve") || text.contains("nodename") || text.contains("dns")
            || text.contains("host not found") {
            return .dnsResolutionFailed
        }
        if text.contains("cancelled") || text.contains("canceled") {
            return .cancelled
        }
        return .unknown
    }

    /// Maps a bucket to the explanation shown to the person running the tool.
    ///
    /// The wording deliberately stops short of naming any application as the
    /// cause. A diagnostic tool measures the network path; it cannot observe
    /// the requests any particular application makes.
    public func explain(_ kind: FailureKind) -> String {
        switch kind {
        case .dnsResolutionFailed:
            return DiagnosticsExplainer.text(
                en: "The host name could not be resolved to any address. The resolver reachable from this device returned no usable answer.",
                ru: "Имя хоста не удалось разрешить ни в один адрес. Доступный системе резолвер не вернул пригодного ответа.")
        case .dnsBlocked:
            return DiagnosticsExplainer.text(
                en: "Resolution timed out with no answer, which is what a filtered or silently dropped DNS path looks like.",
                ru: "Разрешение завершилось по таймауту без ответа — это признак фильтруемого или молча отбрасываемого DNS-трафика.")
        case .tlsHandshakeFailed:
            return DiagnosticsExplainer.text(
                en: "The TCP connection was accepted but the TLS handshake did not complete. Content on this path may be inspected or terminated before it reaches the origin server.",
                ru: "TCP-соединение принято, но TLS-рукопожатие не завершилось. Трафик на этом пути может просматриваться или обрываться до сервера-источника.")
        case .tlsCertificateRejected:
            return DiagnosticsExplainer.text(
                en: "The server presented a certificate the system did not trust. A middlebox that rewrites TLS normally causes exactly this.",
                ru: "Сервер предъявил сертификат, которому система не доверяет. Именно так проявляется устройство, переписывающее TLS.")
        case .tlsCertificateExpired:
            return DiagnosticsExplainer.text(
                en: "The server certificate is outside its validity window, or the device clock disagrees with it.",
                ru: "Сертификат сервера вне срока действия, либо время на устройстве расходится с ним.")
        case .connectionTimedOut:
            return DiagnosticsExplainer.text(
                en: "No response arrived before the deadline. Data was sent but nothing came back.",
                ru: "Ответ не пришёл до истечения срока. Данные отправлены, но ничего не вернулось.")
        case .connectionRefused:
            return DiagnosticsExplainer.text(
                en: "The host answered with a refusal, so something reachable answered. This is not a general connectivity failure.",
                ru: "Хост ответил отказом — значит, отвечает нечто достижимое. Это не общая потеря связности.")
        case .connectionLost:
            return DiagnosticsExplainer.text(
                en: "The connection was established and then dropped mid-transfer.",
                ru: "Соединение было установлено и затем оборвано во время передачи.")
        case .notConnected:
            return DiagnosticsExplainer.text(
                en: "The system reported no usable network path for this attempt.",
                ru: "Система сообщила, что для этой попытки нет пригодного сетевого пути.")
        case .httpError:
            return DiagnosticsExplainer.text(
                en: "A response arrived but carried an error status. The network path itself worked.",
                ru: "Ответ получен, но содержит ошибочный статус. Сам сетевой путь работоспособен.")
        case .tooManyRedirects:
            return DiagnosticsExplainer.text(
                en: "The server kept redirecting. Often a sign of a captive portal or an interception layer.",
                ru: "Сервер непрерывно перенаправляет. Часто это признак captive portal или перехватывающего слоя.")
        case .cancelled:
            return DiagnosticsExplainer.text(
                en: "The request was cancelled before it finished.",
                ru: "Запрос был отменён до завершения.")
        case .unknown:
            return DiagnosticsExplainer.text(
                en: "The failure could not be classified. The raw system error is recorded verbatim in the export.",
                ru: "Сбой не классифицирован. Исходная системная ошибка сохранена дословно в экспорте.")
        }
    }
}