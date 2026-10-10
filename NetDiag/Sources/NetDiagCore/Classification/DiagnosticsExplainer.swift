import Foundation

/// Resolves the display language used in explanations and reports.
///
/// The tool is used on both English and Russian iPhones, so every user-facing
/// string in `NetDiagCore` goes through here. The language is captured once
/// at launch and then read synchronously, because explanations are built on
/// background queues where consulting `Bundle` is not worth the cost.
public enum DiagnosticsExplainer {

    /// Languages this build ships text for.
    public enum Language: String, CaseIterable, Sendable {
        case en
        case ru

        /// Best match for the given locale identifier, defaulting to English.
        public static func match(_ localeIdentifier: String) -> Language {
            let prefix = localeIdentifier.lowercased().prefix(2)
            switch prefix {
            case "ru": return .ru
            default:   return .en
            }
        }
    }

    /// Language used by every explanation built after this is set.
    ///
    /// Defaults to `.en`. Set once at app launch from `Locale.preferredLanguages`.
    public nonisolated(unsafe) private static var current: Language = .en

    public static var language: Language {
        get { current }
        set { current = newValue }
    }

    /// Convenience for tests: set the language and run a body, then restore.
    public static func withLanguage<T>(_ language: Language, _ body: () throws -> T) rethrows -> T {
        let previous = current
        current = language
        defer { current = previous }
        return try body()
    }

    /// Returns the string for the active language.
    public static func text(en: String, ru: String) -> String {
        current == .ru ? ru : en
    }
}

/// The fixed disclaimer shown wherever a result could be over-read.
///
/// A passing probe proves only that one specific path worked at one specific
/// moment. It says nothing about any other host, and it says nothing about
/// what any particular application is able to reach.
public enum DiagnosticDisclaimer {

    public static let probeIsNotAppProof = text(
        en: "A successful probe proves only that this host was reachable over this path at this moment. It does not establish that any other host, or any particular application, is reachable.",
        ru: "Успешная проверка доказывает лишь то, что этот хост был достижим по этому пути в этот момент. Это не означает, что достижим другой хост или конкретное приложение.")

    public static let noTrafficInspection = text(
        en: "This tool measures the network path from this device. It does not read, log, intercept or modify the traffic of any other application.",
        ru: "Инструмент измеряет сетевой путь с этого устройства. Он не читает, не журналирует, не перехватывает и не изменяет трафик других приложений.")

    public static func text(en: String, ru: String) -> String {
        DiagnosticsExplainer.text(en: en, ru: ru)
    }
}