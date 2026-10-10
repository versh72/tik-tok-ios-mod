import SwiftUI
import NetDiagCore

/// Adds a target from free-form input.
///
/// Validation happens as you type against the same `EndpointValidator` the
/// core uses, so the screen cannot accept something the prober would reject.
public struct AddTargetView: View {

    @ObservedObject var model: DiagnosticViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var input: String = ""
    @State private var label: String = ""
    @State private var port: String = "443"
    @State private var path: String = "/"

    public init(model: DiagnosticViewModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(DiagnosticsExplainer.text(
                        en: "example.com",
                        ru: "example.com"), text: $input)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    TextField(DiagnosticsExplainer.text(en: "Label", ru: "Название"),
                              text: $label)

                    TextField(DiagnosticsExplainer.text(en: "Port", ru: "Порт"),
                              text: $port)
                        .keyboardType(.numberPad)

                    TextField(DiagnosticsExplainer.text(en: "Path", ru: "Путь"),
                              text: $path)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text(DiagnosticsExplainer.text(en: "Target", ru: "Цель"))
                } footer: {
                    Text(DiagnosticsExplainer.text(
                        en: "Only https is accepted. A query string you paste is dropped and never recorded.",
                        ru: "Принимается только https. Вставленная строка запроса отбрасывается и никогда не записывается."))
                }

                Section {
                    ForEach(PresetTargets.all) { preset in
                        Button {
                            input = preset.target.host
                            label = preset.target.label
                            port = "443"
                            path = "/"
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.target.label)
                                Text(preset.purpose)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text(DiagnosticsExplainer.text(en: "Suggested", ru: "Предлагаемые"))
                }

                Section {
                    DisclaimerView()
                }
            }
            .navigationTitle(DiagnosticsExplainer.text(en: "Add target", ru: "Новая цель"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(DiagnosticsExplainer.text(en: "Cancel", ru: "Отмена")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(DiagnosticsExplainer.text(en: "Add", ru: "Добавить")) {
                        commit()
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func commit() {
        // Build the string exactly as the validator parses it, so the screen
        // and the prober cannot disagree about what was entered.
        var composed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsedPort = Int(port), parsedPort != 443, !composed.contains(":") {
            composed += ":\(parsedPort)"
        }
        if !path.isEmpty, path != "/", !composed.contains("/") {
            composed += path
        }

        let before = model.targets.count
        model.addTarget(from: composed, label: label)
        if model.targets.count > before {
            dismiss()
        }
    }
}

/// Read-only view of a target.
public struct TargetDetailView: View {
    private let target: ProbeTarget

    public init(target: ProbeTarget) {
        self.target = target
    }

    public var body: some View {
        List {
            Section(DiagnosticsExplainer.text(en: "Target", ru: "Цель")) {
                row(DiagnosticsExplainer.text(en: "Label", ru: "Название"),
                    Redactor.redact(target.label))
                row(DiagnosticsExplainer.text(en: "Host", ru: "Хост"), target.host)
                row(DiagnosticsExplainer.text(en: "Port", ru: "Порт"), "\(target.port)")
                row(DiagnosticsExplainer.text(en: "Path", ru: "Путь"), target.path)
            }

            Section {
                DisclaimerView()
            }
        }
        .navigationTitle(target.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(.secondary)
        }
    }
}