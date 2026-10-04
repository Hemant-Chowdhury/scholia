import AgentKit
import Assistant
import SwiftUI

/// Settings: what the assistant knows about the reader, the prompt texts, and the status of the agents.
public struct SettingsView: View {
    public init() {}

    public var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "person.crop.circle") }
            PromptSettings().tabItem { Label("Prompts", systemImage: "text.bubble") }
            AgentSettings().tabItem { Label("Agents", systemImage: "cpu") }
        }
        .frame(width: 640, height: 600)
    }
}

struct GeneralSettings: View {
    @AppStorage(AssistantModel.aboutMeKey) private var aboutMe = ""

    var body: some View {
        Form {
            Section {
                TextEditor(text: $aboutMe).font(.body).frame(minHeight: 140)
            } header: {
                Text("About me")
            } footer: {
                Text("For example: \"Backend engineer. I know Java and distributed systems. I am new to machine learning.\" The assistant explains at your level.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// Each prompt text can be changed. The changes apply to the next question. An empty field uses the default.
struct PromptSettings: View {
    @State private var templates = PromptTemplates.load(from: .standard)

    private let fields: [(title: String, help: String, keyPath: WritableKeyPath<PromptTemplates, String>)] = [
        ("Role and rules", "The start of each first prompt. Keep the rule about page citations, so that page links work.", \.rules),
        ("Explain (E)", "The task for Explain.", \.explain),
        ("Simplify (S)", "The task for Simplify.", \.simplify),
        ("Define (D)", "The task for Define.", \.define),
        ("Ask (A)", "Comes before your own question.", \.ask),
        ("Quick follow-up: Simpler", "", \.simpler),
        ("Quick follow-up: Give an example", "", \.example),
        ("Quick follow-up: Why does this matter?", "", \.why),
        ("Quick follow-up: Connect to earlier", "", \.connect),
    ]

    var body: some View {
        Form {
            Section {
                Text("The assistant also receives the book context: the location, the text around the selection, related passages and earlier questions. These texts tell it what to do with that context.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(fields, id: \.title) { field in
                Section {
                    TextEditor(text: binding(field.keyPath))
                        .font(.body)
                        .frame(minHeight: field.keyPath == \PromptTemplates.rules ? 150 : 54)
                    HStack {
                        if !field.help.isEmpty { Text(field.help).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        Button("Reset") { templates[keyPath: field.keyPath] = PromptTemplates.standard[keyPath: field.keyPath] }
                            .disabled(templates[keyPath: field.keyPath] == PromptTemplates.standard[keyPath: field.keyPath])
                    }
                } header: {
                    Text(field.title)
                }
            }
            Section {
                Button("Reset all prompts") { templates = .standard }.disabled(templates == .standard)
            }
        }
        .formStyle(.grouped)
        .onChange(of: templates) { templates.save(to: .standard) }
    }

    private func binding(_ keyPath: WritableKeyPath<PromptTemplates, String>) -> Binding<String> {
        Binding(get: { templates[keyPath: keyPath] }, set: { templates[keyPath: keyPath] = $0 })
    }
}

struct AgentSettings: View {
    @State private var agents: [AgentAvailability] = []

    var body: some View {
        Form {
            Section("Agents") {
                if agents.isEmpty { ProgressView().controlSize(.small) }
                ForEach(agents) { availability in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(availability.spec.name)
                            Spacer()
                            Text(status(availability)).foregroundStyle(.secondary)
                        }
                        Text(hint(availability)).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                Button("Check again") { Task { await load() } }
            }
            Section("Safety") {
                Text("Agents can only read and search. They cannot change files, run commands or use your account connectors. Reader refuses each request to read a file outside the book's workspace.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await load() }
    }

    private func load() async {
        agents = await Task.detached { AgentCatalog.all.map(AgentLocator.standard().availability(of:)) }.value
    }

    private func status(_ availability: AgentAvailability) -> String {
        switch availability.status {
        case .ready: "Ready"
        case .notInstalled: "Not installed"
        case .notSupportedYet: "Installed, not supported yet"
        }
    }

    private func hint(_ availability: AgentAvailability) -> String {
        switch availability.status {
        case .ready: availability.spec.note ?? availability.spec.loginHint
        case .notInstalled: availability.spec.installHint
        case .notSupportedYet: availability.spec.note ?? ""
        }
    }
}
