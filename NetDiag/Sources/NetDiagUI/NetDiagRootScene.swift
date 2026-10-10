import SwiftUI
import NetDiagCore

/// Top-level navigation.
///
/// Four screens, matching the four things a person actually does: check,
/// compare, read the log, read the limits.
public struct NetDiagRootScene: View {

    @StateObject private var model: DiagnosticViewModel

    public init() {
        _model = StateObject(wrappedValue: DiagnosticViewModel())
    }

    /// For previews and tests that supply their own model.
    public init(model: @autoclosure @escaping () -> DiagnosticViewModel) {
        _model = StateObject(wrappedValue: model())
    }

    public var body: some View {
        TabView {
            RootView(model: model)
                .tabItem {
                    Label(DiagnosticsExplainer.text(en: "Check", ru: "Проверка"),
                          systemImage: "checkmark.shield")
                }

            NavigationStack {
                CompareView(model: model)
            }
            .tabItem {
                Label(DiagnosticsExplainer.text(en: "Compare", ru: "Сравнение"),
                      systemImage: "arrow.left.arrow.right")
            }

            NavigationStack {
                HistoryView(model: model)
            }
            .tabItem {
                Label(DiagnosticsExplainer.text(en: "History", ru: "История"),
                      systemImage: "clock.arrow.circlepath")
            }

            NavigationStack {
                SettingsView(model: model)
            }
            .tabItem {
                Label(DiagnosticsExplainer.text(en: "About", ru: "О приложении"),
                      systemImage: "info.circle")
            }
        }
    }
}