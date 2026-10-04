import AgentKit
import Assistant
import SwiftUI
import WorkspaceStore

/// The assistant side panel: agent and model, the current thread or the list of threads, and the question field.
struct AssistantPanel: View {
    let reader: ReaderModel
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    private var assistant: AssistantModel { reader.assistant }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if !assistant.agents.isEmpty && assistant.readyAgents.isEmpty {
                AgentSetupView(agents: assistant.agents)
            } else if let thread = assistant.currentThread {
                ThreadView(reader: reader, thread: thread)
            } else {
                ThreadListView(reader: reader)
            }
            Divider()
            inputBar
        }
        .frame(minWidth: 320)
        .task { await assistant.refreshAgents() }
        .onChange(of: reader.pendingAsk?.text) { if reader.pendingAsk != nil { fieldFocused = true } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if assistant.currentThread != nil {
                Button { assistant.closeThread() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                    .help("All questions")
                    .disabled(assistant.isRunning)
            }
            Picker("Agent", selection: Binding(get: { assistant.selectedAgentID }, set: { assistant.selectAgent($0) })) {
                ForEach(assistant.readyAgents) { Text($0.spec.name).tag($0.spec.id) }
            }
            .labelsHidden()
            .fixedSize()
            .disabled(assistant.isRunning || assistant.readyAgents.count < 2)
            if !assistant.visibleModelChoices.isEmpty {
                Picker("Model", selection: Binding(get: { assistant.selectedModel ?? "" }, set: { assistant.selectModel($0) })) {
                    if assistant.selectedModel == nil { Text("Default model").tag("") }
                    ForEach(assistant.visibleModelChoices, id: \.value) { Text($0.name).tag($0.value) }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(assistant.isRunning)
            }
            Spacer()
        }
        .padding(10)
    }

    @ViewBuilder private var inputBar: some View {
        HStack(spacing: 8) {
            if let ask = reader.pendingAsk {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask about: \(ask.text.prefix(80))…").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    TextField("Your question", text: $draft, axis: .vertical)
                        .focused($fieldFocused)
                        .lineLimit(1...5)
                        .onSubmit(send)
                }
                Button("Cancel") { reader.cancelAsk(); draft = "" }
            } else if assistant.currentThread != nil {
                TextField("Ask a follow-up…", text: $draft, axis: .vertical)
                    .focused($fieldFocused)
                    .lineLimit(1...5)
                    .onSubmit(send)
                    .disabled(assistant.isRunning)
            } else {
                Text("Select text, then press E (Explain), S, D or A.").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }
            if assistant.isRunning {
                Button { assistant.stop() } label: { Label("Stop", systemImage: "stop.circle.fill") }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).help("Stop")
            } else if reader.pendingAsk != nil || assistant.currentThread != nil {
                Button(action: send) { Label("Send", systemImage: "arrow.up.circle.fill") }
                    .labelStyle(.iconOnly).buttonStyle(.borderless).font(.title2)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(10)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if reader.pendingAsk != nil { reader.submitAsk(text) } else { assistant.followUp(text) }
        draft = ""
    }
}

/// One thread: the quoted selection, the messages, the agent activity and quick follow-ups.
struct ThreadView: View {
    let reader: ReaderModel
    let thread: ThreadRecord

    private var assistant: AssistantModel { reader.assistant }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    quote
                    ForEach(assistant.messages) { message in
                        if message.role == "user" {
                            Text(message.text)
                                .font(.callout.weight(.semibold))
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        } else {
                            answer(message)
                        }
                    }
                    if let activity = assistant.activity {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(activity).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    if !assistant.isRunning, assistant.messages.last?.status == "complete" {
                        quickFollowUps
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(14)
            }
            .onChange(of: assistant.messages.last?.text) { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: thread.id) { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    private var quote: some View {
        Button { reader.open(thread) } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(assistant.currentAnchor?.text ?? thread.title)
                    .font(.callout).italic().lineLimit(6).multilineTextAlignment(.leading)
                Text("Page \(thread.firstPage + 1)" + (assistant.currentAnchor.map { $0.structuralPath.isEmpty ? "" : " · \($0.structuralPath)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 2).fill(.tint).frame(width: 3).padding(.vertical, 6) }
        }
        .buttonStyle(.plain)
        .help("Show in the PDF")
    }

    @ViewBuilder private func answer(_ message: AssistantModel.ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !message.text.isEmpty { MarkdownView(text: message.text) }
            switch message.status {
            case "failed":
                Label(message.error ?? "The agent did not answer.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red).font(.callout)
                Button("Try again") { assistant.retry() }.disabled(assistant.isRunning)
            case "cancelled":
                Text("Stopped.").font(.caption).foregroundStyle(.secondary)
            default:
                EmptyView()
            }
        }
    }

    private var quickFollowUps: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(QuickFollowUp.allCases, id: \.self) { quick in
                    Button(quick.title) { assistant.quick(quick) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
        }
    }
}

/// The threads of the document, with the threads near the current page first.
struct ThreadListView: View {
    let reader: ReaderModel

    private var assistant: AssistantModel { reader.assistant }

    var body: some View {
        List {
            if assistant.allThreads.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ask about any part of the book").font(.headline)
                    Text("Option-click a paragraph to select it, or drag to select text. Then press E to explain it, S to simplify it, D to define its terms, or A to ask your own question.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            if !assistant.pageThreads.isEmpty {
                Section("Earlier on this page") { rows(assistant.pageThreads) }
            }
            if !assistant.allThreads.isEmpty {
                Section("All questions (\(assistant.allThreads.count))") { rows(assistant.allThreads) }
            }
        }
    }

    private func rows(_ threads: [ThreadRecord]) -> some View {
        ForEach(threads) { thread in
            Button { reader.open(thread) } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(thread.title).lineLimit(2)
                    Text("Page \(thread.firstPage + 1)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
}

/// Shown when no agent is ready: what to install, and how.
struct AgentSetupView: View {
    let agents: [AgentAvailability]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Set up an agent").font(.headline)
                Text("Reader uses the AI agents on your Mac and the subscriptions that you already have.")
                    .foregroundStyle(.secondary)
                ForEach(agents) { AgentStatusRow(availability: $0) }
            }
            .padding(14)
        }
    }
}

struct AgentStatusRow: View {
    let availability: AgentAvailability

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(availability.spec.name).font(.body.weight(.medium))
                Spacer()
                Text(statusText).font(.caption).foregroundStyle(statusColor)
            }
            if case .notInstalled = availability.status {
                Text(availability.spec.installHint).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            } else if let note = availability.spec.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var statusText: String {
        switch availability.status {
        case .ready: "Ready"
        case .notInstalled: "Not installed"
        case .notSupportedYet: "Not supported yet"
        }
    }

    private var statusColor: Color {
        switch availability.status {
        case .ready: .green
        case .notInstalled: .secondary
        case .notSupportedYet: .orange
        }
    }
}
