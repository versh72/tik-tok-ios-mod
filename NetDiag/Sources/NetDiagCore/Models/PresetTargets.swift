import Foundation

/// Endpoints the tool offers out of the box.
///
/// These are deliberately generic public reference endpoints used for network
/// reachability checks. They are not application-specific, they carry no
/// account data, and the person using the tool can delete any of them and add
/// their own.
///
/// Nothing here should be read as "these hosts must work for your app to
/// work". See `DiagnosticDisclaimer.probeIsNotAppProof`.
public enum PresetTargets {

    public struct Preset: Identifiable, Sendable {
        public let id: String
        public let target: ProbeTarget
        public let purpose: String
    }

    public static let all: [Preset] = [
        Preset(
            id: "apple",
            target: ProbeTarget(label: "Apple", host: "www.apple.com"),
            purpose: DiagnosticsExplainer.text(
                en: "A large CDN-backed vendor site. A reasonable control when the rest fails.",
                ru: "Крупный сайт вендора за CDN. Разумный контрольный адрес, когда остальное не работает.")
        ),
        Preset(
            id: "cloudflare-dns",
            target: ProbeTarget(label: "Cloudflare DNS", host: "one.one.one.one"),
            purpose: DiagnosticsExplainer.text(
                en: "A public DNS resolver. Useful as a target itself and as a hint about reachability.",
                ru: "Публичный DNS-резолвер. Полезен и как цель, и как косвенный признак достижимости.")
        ),
        Preset(
            id: "wikipedia",
            target: ProbeTarget(label: "Wikipedia", host: "www.wikipedia.org"),
            purpose: DiagnosticsExplainer.text(
                en: "A site served from many regions, useful for spotting regional filtering.",
                ru: "Сайт, отдаваемый из многих регионов; полезен для выявления региональной фильтрации.")
        ),
        Preset(
            id: "github",
            target: ProbeTarget(label: "GitHub", host: "github.com"),
            purpose: DiagnosticsExplainer.text(
                en: "A widely used developer host, usually reachable even on restrictive networks.",
                ru: "Широко используемый хостинг для разработчиков, обычно доступен даже в ограниченных сетях.")
        ),
        Preset(
            id: "iana",
            target: ProbeTarget(label: "IANA", host: "www.iana.org"),
            purpose: DiagnosticsExplainer.text(
                en: "A small, static reference site. Little to fail, so a failure here is informative.",
                ru: "Небольшой статический справочный сайт. Ломаться почти нечему, поэтому сбой здесь показателен.")
        )
    ]

    public static var targets: [ProbeTarget] { all.map(\.target) }
}