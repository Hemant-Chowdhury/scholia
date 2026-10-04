import AgentKit
import Assistant
import SwiftUI

/// Settings: what the assistant knows about the reader, and the status of the agents.
struct SettingsView: View {
    @AppStorage(AssistantModel.aboutMeKey) private var aboutMe = ""
    @State private var agents: [AgentAvailability] = []

    var body: some View {
        Form {
            Section {
                TextEditor(text: $aboutMe)
                    .font(.body)
                    .frame(minHeight: 110)
            } header: {
                Text("About me")
            } footer: {
                Text("For example: \"Backend engineer. I know Java and distributed systems. I am new to machine learning.\" The assistant explains at your level.")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 520)
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
