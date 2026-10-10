import SwiftUI
import NetDiagCore

/// The screen people land on. Targets, the run button, and the current
/// verdict — with the disclaimer above the fold rather than buried in an
/// about screen.
public struct RootView: View {

    @ObservedObject private var model: DiagnosticViewModel
    @State private var showingAddTarget = false

    public init(model: DiagnosticViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            List {
                statusSection
                targetsSection
                if let run = model.currentRun {
                    resultsSection(run)
                }
                disclaimerSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(DiagnosticsExplainer.text(
                en: "Network Check",
                ru: "Проверка сети"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddTarget = true
                    } label: {
                        Label(DiagnosticsExplainer.text(en: "Add target", ru: "Добавить"),
                              systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddTarget) {
                AddTargetView(model: model)
            }
        }
    }

    // MARK: - Status

    private var statusSection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(DiagnosticsExplainer.text(en: "Current path", ru: "Текущий путь"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(model.currentPath.summary)
                        .font(.body.weight(.medium))
                }
                Spacer()
                if model.isRunning {
                    ProgressView()
                } else {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(DiagnosticsExplainer.text(en: "Scenario", ru: "Сценарий"))
                    .foregroundStyle(.secondary)
                TextField(
                    DiagnosticsExplainer.text(
                        en: "e.g. VPN on, VPN off",
                        ru: "например: VPN вкл, VPN выкл"),
                    text: $model.scenario
                )
                .multilineTextAlignment(.trailing)
            }

            if model.isRunning {
                ProgressView(value: Double(model.completedCount),
                             total: Double(max(model.targets.count, 1))) {
                    Text(model.progressLabel)
                        .font(.caption)
                        .lineLimit(1)
                }
            }

            if let message = model.validationMessage {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            HStack {
                if model.isRunning {
                    Button(role: .destructive) {
                        model.cancelRun()
                    } label: {
                        Label(DiagnosticsExplainer.text(en: "Stop", ru: "Остановить"),
                              systemImage: "stop.circle")
                    }
                } else {
                    Button {
                        model.startRun()
                    } label: {
                        Label(DiagnosticsExplainer.text(en: "Run check", ru: "Запустить"),
                              systemImage: "play.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.targets.isEmpty)
                }
            }
        }
    }

    // MARK: - Targets

    private var targetsSection: some View {
        Section {
            if model.targets.isEmpty {
                Text(DiagnosticsExplainer.text(
                    en: "No targets. Add one to run a check.",
                    ru: "Целей нет. Добавьте цель для проверки."))
                .font(.footnote)
                .foregroundStyle(.secondary)
            } else {
                ForEach(model.targets) { target in
                    NavigationLink {
                        TargetDetailView(target: target)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(target.label)
                            Text(target.authority + target.path)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    for index in offsets { model.removeTarget(model.targets[index]) }
                }
                .onMove(perform: model.moveTargets)
            }
        } header: {
            Text(DiagnosticsExplainer.text(en: "Targets", ru: "Цели"))
        } footer: {
            Text(DiagnosticsExplainer.text(
                en: "Any host you enter is contacted directly by this app. Choose hosts you are allowed to contact.",
                ru: "Любой введённый хост запрашивается самим приложением. Выбирайте хосты, которые вам разрешено запрашивать."))
        }
    }

    // MARK: - Results

    private func resultsSection(_ run: DiagnosticRun) -> some View {
        Section {
            ForEach(run.results) { result in
                NavigationLink {
                    ResultDetailView(result: result)
                } label: {
                    HStack {
                        GradeBadge(result.overallOutcome)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.target.label)
                            Text(result.target.authority)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let status = result.https.statusCode {
                            Text("\(status)")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else if let kind = result.https.errorKind {
                            Text(kind.identifier)
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        } header: {
            Text(DiagnosticsExplainer.text(en: "Results", ru: "Результаты"))
        } footer: {
            Text(model.summaryLine)
        }
    }

    private var disclaimerSection: some View {
        Section {
            DisclaimerView()
        }
    }
}