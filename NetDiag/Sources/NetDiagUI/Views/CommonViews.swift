import SwiftUI
import NetDiagCore

/// Small pieces shared across the screens.

public struct GradeBadge: View {
    private let grade: Verdict.Grade

    public init(_ grade: Verdict.Grade) { self.grade = grade }

    public var body: some View {
        Image(systemName: grade.symbolName)
            .foregroundStyle(color)
            .accessibilityLabel(grade.localizedName)
    }

    private var color: Color {
        switch grade {
        case .passed:  return .green
        case .failed:  return .red
        case .skipped: return .secondary
        }
    }
}

/// The standing disclaimer. Repeated in several places on purpose: it is the
/// single most important thing for the reader not to over-interpret.
public struct DisclaimerView: View {
    private let style: Style

    public enum Style { case prominent, inline }

    public init(style: Style = .inline) { self.style = style }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(DiagnosticsExplainer.text(
                    en: "What this tool does not do",
                    ru: "Что этот инструмент не делает"))
            } icon: {
                Image(systemName: "hand.raised")
            }
            .font(.footnote.weight(.semibold))

            bullet(DiagnosticDisclaimer.probeIsNotAppProof)
            bullet(DiagnosticDisclaimer.noTrafficInspection)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.vertical, style == .prominent ? 12 : 4)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("•")
            Text(text)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// One row per stage of a probe.
public struct StageRow: View {
    private let title: String
    private let grade: Verdict.Grade
    private let detail: String

    public init(title: String, grade: Verdict.Grade, detail: String) {
        self.title = title
        self.grade = grade
        self.detail = detail
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            GradeBadge(grade)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

/// Empty-state placeholder that explains what the screen is for instead of
/// showing a bare list.
///
/// Written by hand rather than using `ContentUnavailableView` so the package
/// keeps its iOS 16 deployment target.
public struct EmptyHint<Content: View>: View {
    private let title: String
    private let message: String
    private let content: () -> Content

    public init(
        title: String,
        message: String,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.message = message
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            content()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 24)
    }
}