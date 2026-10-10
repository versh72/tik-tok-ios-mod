import Foundation
import SwiftUI
import NetDiagCore
import NetDiagEngine

/// Owns the run in progress and exposes it to the views.
///
/// Split from the views so that the logic has no SwiftUI dependency and can be
/// exercised without a UI. Everything the user sees is derived from `state`.
@MainActor
public final class DiagnosticViewModel: ObservableObject {

    // MARK: - Observable state

    @Published public var targets: [ProbeTarget] = PresetTargets.targets
    @Published public var scenario: String = ""
    @Published public var currentRun: DiagnosticRun?
    @Published public var isRunning = false
    @Published public var progressLabel: String = ""
    @Published public var completedCount = 0
    @Published public var log = DiagnosticLog()
    @Published public var validationMessage: String?
    @Published public var lastExport: ReportBuilder.Report?

    // MARK: - Collaborators

    private let store: RunStore
    private let coordinator: ProbeCoordinator
    private let pathObserver: NetworkPathObserver
    private var runTask: Task<Void, Never>?

    public init(
        store: RunStore = RunStore(),
        coordinator: ProbeCoordinator? = nil,
        pathObserver: NetworkPathObserver = NetworkPathObserver()
    ) {
        self.store = store
        self.pathObserver = pathObserver

        if let coordinator {
            self.coordinator = coordinator
        } else {
            self.coordinator = ProbeCoordinator(
                dns: SystemDNSResolver(),
                tls: NetworkTLSProber(),
                https: URLSessionHTTPSProber()
            )
        }

        // Explanations follow the device language.
        DiagnosticsExplainer.language = .match(Locale.preferredLanguages.first ?? "en")

        log.log(.info, "Session started.", detail: "No traffic of other apps is read.")
    }

    deinit {
        runTask?.cancel()
        pathObserver.stop()
    }

    // MARK: - Derived

    public var runs: [DiagnosticRun] { store.runs }

    public var comparison: RunComparison? {
        guard let pair = store.lastTwo else { return nil }
        return RunComparator.compare(baseline: pair.baseline, candidate: pair.candidate)
    }

    public var currentPath: PathSnapshot { pathObserver.current }

    public var summaryLine: String {
        guard let run = currentRun else {
            return DiagnosticsExplainer.text(
                en: "Run a check to see results.",
                ru: "Запустите проверку, чтобы увидеть результаты.")
        }
        return Verdict.summary(for: run)
    }

    // MARK: - Targets

    public func addTarget(from input: String, label: String) {
        do {
            let target = try EndpointValidator.makeTarget(
                label: label,
                input: input,
                scenario: scenario
            )
            targets.append(target)
            validationMessage = nil
            log.log(.info, "Added target.", detail: "\(target.authority)\(target.path)")
        } catch let error as EndpointValidator.ValidationError {
            validationMessage = error.message
            log.log(.warning, "Target rejected.", detail: error.message)
        } catch {
            validationMessage = Redactor.redactFreeText(error.localizedDescription)
            log.log(.warning, "Target rejected.")
        }
    }

    public func updateTarget(_ target: ProbeTarget) {
        guard let index = targets.firstIndex(where: { $0.id == target.id }) else { return }
        targets[index] = target
    }

    public func removeTarget(_ target: ProbeTarget) {
        targets.removeAll { $0.id == target.id }
    }

    public func moveTargets(from offsets: IndexSet, to destination: Int) {
        targets.move(fromOffsets: offsets, toOffset: destination)
    }

    // MARK: - Running

    public func startRun() {
        guard !isRunning else { return }
        guard !targets.isEmpty else {
            validationMessage = DiagnosticsExplainer.text(
                en: "Add at least one target before running a check.",
                ru: "Добавьте хотя бы одну цель перед запуском проверки.")
            return
        }

        isRunning = true
        completedCount = 0
        validationMessage = nil
        progressLabel = ""

        runTask = Task { [weak self] in
            guard let self else { return }
            await self.executeRun()
        }
    }

    public func cancelRun() {
        runTask?.cancel()
        runTask = nil
        isRunning = false
        progressLabel = ""
    }

    private func executeRun() async {
        pathObserver.start { [weak self] _ in
            // Path updates are reflected through `currentPath`; the run
            // captures a snapshot at start and at end rather than mid-flight,
            // because an interface can flap mid-run and make the numbers
            // impossible to compare.
        }
        let startPath = await pathObserver.waitForFirstUpdate()

        let snapshotTargets = targets
        var run = DiagnosticRun(
            scenario: scenario,
            startedAt: Date(),
            pathAtStart: startPath
        )

        log.log(.info, "Run started.", detail: "\(snapshotTargets.count) target(s), path \(startPath.summary)")

        for (index, target) in snapshotTargets.enumerated() {
            if Task.isCancelled { break }

            progressLabel = target.authority
            completedCount = index

            let result = await coordinator.probe(target, path: startPath)
            run.results.append(result)

            switch result.overallOutcome {
            case .passed:
                log.log(.success, "\(target.authority) completed.", detail: result.https.explanation)
            case .failed:
                log.log(.failure, "\(target.authority) failed.",
                        detail: result.https.errorKind?.identifier)
            case .skipped:
                log.log(.warning, "\(target.authority) did not complete all stages.")
            }
        }

        run.finishedAt = Date()
        run.pathAtEnd = pathObserver.current

        guard !Task.isCancelled else {
            isRunning = false
            progressLabel = ""
            return
        }

        currentRun = run
        store.append(run)
        isRunning = false
        completedCount = snapshotTargets.count
        progressLabel = ""

        log.log(.info, "Run finished.",
                detail: "\(run.succeededCount) passed, \(run.failedCount) failed in \(Int(run.durationMilliseconds)) ms")
    }

    // MARK: - Export

    public func makeReport(for run: DiagnosticRun) -> ReportBuilder.Report {
        let report = ReportBuilder().report(for: run)
        lastExport = report
        log.log(.info, "Report generated.", detail: "\(report.markdown.count) bytes of Markdown")
        return report
    }

    public func clearHistory() {
        store.removeAll()
        currentRun = nil
        log.clear()
        log.log(.info, "History cleared. Nothing had left the device.")
    }
}