import SwiftUI
import NetDiagCore

/// The comparison screen — the reason this tool exists.
///
/// One target, two network configurations, side by side. A result that only
/// ever looks at a single configuration cannot separate a device problem from
/// a path problem; a difference between two runs can.
public struct CompareView: View {

    @ObservedObject private var model: DiagnosticViewModel

    public init(model: DiagnosticViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if let comparison = model.comparison {
                List {
                    Section {
                        summary(comparison)
                    }

                    Section(DiagnosticsExplainer.text(en: "Per target", ru: "По целям")) {
                        ForEach(comparison.deltas) { delta in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    GradeBadge(delta.beforeGrade)
                                    Image(systemName: "arrow.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    GradeBadge(delta.afterGrade)
                                    Spacer()
                                    if delta.changed {
                                        Text(DiagnosticsExplainer.text(
                                            en: "changed",
                                            ru: "изменилось"))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.orange)
                                    }
                                }

                                Text(delta.authority)
                                    .font(.subheadline)

                                if let change = delta.changeDescription {
                                    Text(change)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Section {
                        DisclaimerView(style: .prominent)
                    }
                }
            } else {
                EmptyHint(
                    title: DiagnosticsExplainer.text(
                        en: "Nothing to compare yet",
                        ru: "Пока нечего сравнивать"),
                    message: DiagnosticsExplainer.text(
                        en: "Run the check twice: once on your normal connection, then again with your VPN on or off. Tag each run with a scenario.",
                        ru: "Запустите проверку дважды: сначала на обычном подключении, затем с включённым или выключенным VPN. Пометьте каждый запуск сценарием.")
                ) {
                    EmptyView()
                }
            }
        }
        .navigationTitle(DiagnosticsExplainer.text(en: "Compare", ru: "Сравнение"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func summary(_ comparison: RunComparison) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            scenarioRow(
                DiagnosticsExplainer.text(en: "Baseline", ru: "База"),
                comparison.baseline.scenario,
                comparison.baseline.pathAtStart.summary
            )
            scenarioRow(
                DiagnosticsExplainer.text(en: "Candidate", ru: "Сравнение"),
                comparison.candidate.scenario,
                comparison.candidate.pathAtStart.summary
            )
            Divider()
            Text(DiagnosticsExplainer.text(
                en: "\(comparison.changedCount) of \(comparison.deltas.count) targets changed between the two runs.",
                ru: "\(comparison.changedCount) из \(comparison.deltas.count) целей изменились между запусками."))
            .font(.subheadline)
        }
    }

    private func scenarioRow(_ title: String, _ scenario: String, _ path: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(scenario.isEmpty
                     ? DiagnosticsExplainer.text(en: "(unnamed)", ru: "(без названия)")
                     : scenario)
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

/// Full history, each run tappable for its report.
public struct HistoryView: View {

    @ObservedObject private var model: DiagnosticViewModel

    public init(model: DiagnosticViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            if model.runs.isEmpty {
                EmptyHint(
                    title: DiagnosticsExplainer.text(
                        en: "No runs yet", ru: "Запусков пока нет"),
                    message: DiagnosticsExplainer.text(
                        en: "Runs are kept in memory only and disappear when the app closes.",
                        ru: "Запуски хранятся только в памяти и исчезают при закрытии приложения.")
                ) {
                    EmptyView()
                }
            } else {
                List {
                    ForEach(model.runs.reversed()) { run in
                        NavigationLink {
                            ReportView(model: model, run: run)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(run.scenario.isEmpty
                                     ? DiagnosticsExplainer.text(
                                        en: "Unnamed run", ru: "Без названия")
                                     : run.scenario)
                                HStack(spacing: 8) {
                                    Text(run.startedAt.formatted(date: .abbreviated,
                                                                time: .shortened))
                                    Text("·")
                                    Text(run.pathAtStart.summary)
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                Text(DiagnosticsExplainer.text(
                                    en: "\(run.succeededCount) passed, \(run.failedCount) failed",
                                    ru: "успешно \(run.succeededCount), сбоев \(run.failedCount)"))
                                .font(.caption)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(DiagnosticsExplainer.text(en: "History", ru: "История"))
    }
}

/// Renders the shareable report.
public struct ReportView: View {

    @ObservedObject private var model: DiagnosticViewModel
    private let run: DiagnosticRun
    @State private var shareURL: URL?

    public init(model: DiagnosticViewModel, run: DiagnosticRun) {
        self.model = model
        self.run = run
    }

    public var body: some View {
        ScrollView {
            Text(model.makeReport(for: run).markdown)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(DiagnosticsExplainer.text(en: "Report", ru: "Отчёт"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: model.makeReport(for: run).markdown) {
                    Label(DiagnosticsExplainer.text(en: "Share", ru: "Поделиться"),
                          systemImage: "square.and.arrow.up")
                }
            }
        }
    }
}

/// Local log. Every line was redacted before it was written.
public struct LogView: View {

    @ObservedObject private var model: DiagnosticViewModel

    public init(model: DiagnosticViewModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section {
                DisclaimerView(style: .prominent)
            }

            Section(DiagnosticsExplainer.text(en: "Entries", ru: "Записи")) {
                if model.log.entries.isEmpty {
                    Text(DiagnosticsExplainer.text(en: "Empty.", ru: "Пусто."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.log.entries.reversed()) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(entry.level.localizedName)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(color(for: entry.level))
                                Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.message)
                                .font(.footnote)
                            if let detail = entry.detail {
                                Text(detail)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(.vertical, 1)
                    }
                }
            }
        }
        .navigationTitle(DiagnosticsExplainer.text(en: "Log", ru: "Журнал"))
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                ShareLink(item: model.log.plainText()) {
                    Label(DiagnosticsExplainer.text(en: "Share", ru: "Поделиться"),
                          systemImage: "square.and.arrow.up")
                }
            }
        }
    }

    private func color(for level: DiagnosticLog.Entry.Level) -> Color {
        switch level {
        case .info:    return .secondary
        case .warning: return .orange
        case .failure: return .red
        case .success: return .green
        }
    }
}

/// Settings. Deliberately short: there is nothing to configure, because the
/// tool collects nothing.
public struct SettingsView: View {

    @ObservedObject private var model: DiagnosticViewModel

    public init(model: DiagnosticViewModel) {
        self.model = model
    }

    public var body: some View {
        List {
            Section(DiagnosticsExplainer.text(en: "What is stored", ru: "Что сохраняется")) {
                Text(DiagnosticsExplainer.text(
                    en: "Nothing leaves this device. Runs live in memory and are gone when the app closes. The log is redacted before it is written, so a token or e-mail pasted into a field by mistake is masked out.",
                    ru: "Ничего не покидает устройство. Запуски живут в памяти и исчезают при закрытии приложения. Журнал редактируется до записи, поэтому случайно вставленный токен или адрес почты будет замаскирован."))
                .font(.footnote)
            }

            Section(DiagnosticsExplainer.text(en: "Limits", ru: "Ограничения")) {
                Text(model.currentPath.vpnCaveat)
                    .font(.footnote)
                Text(DiagnosticsExplainer.text(
                    en: "This app cannot see, log or modify another app's traffic, and it cannot see what any particular app is doing.",
                    ru: "Приложение не видит, не журналирует и не изменяет трафик других приложений и не видит, что делает конкретное приложение."))
                .font(.footnote)
            }

            Section {
                Button(role: .destructive) {
                    model.clearHistory()
                } label: {
                    Label(DiagnosticsExplainer.text(en: "Clear history", ru: "Очистить историю"),
                          systemImage: "trash")
                }
            }
        }
        .navigationTitle(DiagnosticsExplainer.text(en: "About", ru: "О приложении"))
    }
}