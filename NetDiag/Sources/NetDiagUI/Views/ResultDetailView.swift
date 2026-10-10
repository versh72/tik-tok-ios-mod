import SwiftUI
import NetDiagCore

/// Full detail for one target: every stage, every measurement, and the raw
/// system error next to the plain-language explanation.
public struct ResultDetailView: View {

    private let result: TargetResult

    public init(result: TargetResult) {
        self.result = result
    }

    public var body: some View {
        List {
            Section {
                StageRow(
                    title: DiagnosticsExplainer.text(en: "DNS", ru: "DNS"),
                    grade: result.dns.outcome.grade,
                    detail: dnsDetail
                )
                StageRow(
                    title: DiagnosticsExplainer.text(en: "TLS", ru: "TLS"),
                    grade: result.tls.outcome.grade,
                    detail: tlsDetail
                )
                StageRow(
                    title: "HTTPS",
                    grade: result.https.outcome.grade,
                    detail: httpsDetail
                )
            } header: {
                Text(DiagnosticsExplainer.text(en: "Stages", ru: "Этапы"))
            }

            Section(DiagnosticsExplainer.text(en: "Explanation", ru: "Объяснение")) {
                explanation(result.dns.explanation)
                explanation(result.tls.explanation)
                explanation(result.https.explanation)
            }

            if let kind = result.https.errorKind {
                Section(DiagnosticsExplainer.text(en: "Failure bucket", ru: "Класс сбоя")) {
                    LabeledContent(DiagnosticsExplainer.text(en: "Bucket", ru: "Класс")) {
                        Text(kind.identifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.red)
                    }
                }
            }

            let rawErrors = [
                result.dns.systemError,
                result.tls.systemError,
                result.https.systemError
            ].compactMap { $0 }

            if !rawErrors.isEmpty {
                Section(DiagnosticsExplainer.text(en: "Raw system errors", ru: "Системные ошибки")) {
                    ForEach(rawErrors, id: \.self) { line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                LabeledContent(DiagnosticsExplainer.text(en: "Path at start", ru: "Путь в начале")) {
                    Text(result.pathAtStart.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                DisclaimerView()
            }
        }
        .navigationTitle(result.target.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Details

    private var dnsDetail: String {
        switch result.dns.outcome {
        case .resolved:
            var text = result.dns.addresses.joined(separator: ", ")
            if let ms = result.dns.milliseconds { text += " · \(Int(ms)) ms" }
            return text
        case .failed:
            return result.dns.systemError ?? ""
        case .skipped:
            return ""
        }
    }

    private var tlsDetail: String {
        switch result.tls.outcome {
        case .established:
            var parts: [String] = []
            if let proto = result.tls.negotiatedProtocol { parts.append(proto) }
            if let cipher = result.tls.negotiatedCipherSuite { parts.append(cipher) }
            if let subject = result.tls.certificateSubject { parts.append("CN=\(subject)") }
            if let notAfter = result.tls.certificateExpiresInSeconds {
                parts.append(notAfter >= 0
                    ? DiagnosticsExplainer.text(
                        en: "expires in \(Int(notAfter / 86_400)) d",
                        ru: "истекает через \(Int(notAfter / 86_400)) дн.")
                    : DiagnosticsExplainer.text(en: "already expired", ru: "уже истёк"))
            }
            return parts.joined(separator: " · ")
        case .failed:
            return result.tls.systemError ?? ""
        case .skipped:
            return ""
        }
    }

    private var httpsDetail: String {
        switch result.https.outcome {
        case .completed:
            var parts: [String] = []
            if let status = result.https.statusCode { parts.append("HTTP \(status)") }
            if let ttfb = result.https.timeToFirstByteMilliseconds {
                parts.append(DiagnosticsExplainer.text(
                    en: "first byte \(Int(ttfb)) ms",
                    ru: "первый байт \(Int(ttfb)) мс"))
            }
            if let total = result.https.milliseconds {
                parts.append(DiagnosticsExplainer.text(
                    en: "total \(Int(total)) ms",
                    ru: "всего \(Int(total)) мс"))
            }
            if result.https.redirects > 0 { parts.append("\(result.https.redirects) redirects") }
            return parts.joined(separator: " · ")
        case .failed:
            return result.https.systemError ?? ""
        case .skipped:
            return ""
        }
    }

    @ViewBuilder
    private func explanation(_ text: String) -> some View {
        if !text.isEmpty {
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}