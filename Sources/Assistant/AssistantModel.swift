import AgentKit
import DocumentKit
import Foundation
import Observation
import WorkspaceStore

/// The assistant of one reader window: it runs actions on selections, streams answers, and keeps threads.
@MainActor
@Observable
public final class AssistantModel {
    public static let aboutMeKey = "aboutMe"
    static let agentKey = "assistant.agent"

    public struct ChatMessage: Identifiable, Equatable, Sendable {
        public let id: String
        public let role: String
        public let action: String?
        public var text: String
        public var status: String
        public var error: String?
        public let createdAt: Date
    }

    public private(set) var agents: [AgentAvailability] = []
    public private(set) var selectedAgentID: String
    public private(set) var modelChoices: [ACPChoice] = []
    public private(set) var selectedModel: String?
    public private(set) var currentThread: ThreadRecord?
    public private(set) var currentAnchor: AnchorRecord?
    public private(set) var messages: [ChatMessage] = []
    public private(set) var isRunning = false
    /// A short status line, for example the tool that the agent uses now.
    public private(set) var activity: String?
    public private(set) var pageThreads: [ThreadRecord] = []
    public private(set) var allThreads: [ThreadRecord] = []
    public var errorMessage: String?

    public let workspace: OpenedWorkspace
    @ObservationIgnored private let source: PDFDocumentSource
    @ObservationIgnored private let outline: [OutlineEntry]
    @ObservationIgnored private let backend: AgentBackend
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var sessions: [String: (agent: String, model: String?, handle: AgentSessionHandle)] = [:]
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var runningHandle: AgentSessionHandle?
    @ObservationIgnored private var currentPage = 0
    @ObservationIgnored private var lastRun: (userText: String, action: String, prompts: Prompts)?
    @ObservationIgnored private var runID: UUID?

    public init(workspace: OpenedWorkspace, source: PDFDocumentSource, backend: AgentBackend, defaults: UserDefaults = .standard) {
        self.workspace = workspace
        self.source = source
        self.outline = source.outline
        self.backend = backend
        self.defaults = defaults
        self.selectedAgentID = defaults.string(forKey: Self.agentKey) ?? AgentCatalog.claude.id
        self.selectedModel = defaults.string(forKey: Self.modelKey(selectedAgentID))
            ?? AgentCatalog.all.first { $0.id == selectedAgentID }?.defaultModel
        reloadThreads()
    }

    // MARK: Agents and models

    public var readyAgents: [AgentAvailability] { agents.filter { $0.status == .ready } }

    public var selectedAgent: AgentSpec { AgentCatalog.all.first { $0.id == selectedAgentID } ?? AgentCatalog.claude }

    public func refreshAgents() async {
        agents = await backend.availability()
        if !readyAgents.contains(where: { $0.spec.id == selectedAgentID }), let first = readyAgents.first {
            selectAgent(first.spec.id)
        }
    }

    public func selectAgent(_ id: String) {
        guard id != selectedAgentID else { return }
        selectedAgentID = id
        defaults.set(id, forKey: Self.agentKey)
        selectedModel = defaults.string(forKey: Self.modelKey(id)) ?? selectedAgent.defaultModel
        modelChoices = []
    }

    /// The models to show: the session's list, or the agent's known models before the first session.
    public var visibleModelChoices: [ACPChoice] { modelChoices.isEmpty ? selectedAgent.knownModels : modelChoices }

    public func selectModel(_ value: String) {
        selectedModel = value
        defaults.set(value, forKey: Self.modelKey(selectedAgentID))
    }

    private static func modelKey(_ agentID: String) -> String { "assistant.model.\(agentID)" }

    // MARK: Threads

    public func pageChanged(_ pageIndex: Int) {
        currentPage = pageIndex
        pageThreads = (try? workspace.database.threads(documentID: workspace.document.id,
                                                       pages: max(pageIndex - 1, 0)..<(pageIndex + 2))) ?? []
    }

    public func open(thread: ThreadRecord) {
        guard !isRunning else { return }
        currentThread = thread
        currentAnchor = thread.anchorID.flatMap { try? workspace.database.anchor(id: $0) }
        messages = ((try? workspace.database.messages(threadID: thread.id)) ?? []).map(Self.chat)
        errorMessage = nil
    }

    public func closeThread() {
        guard !isRunning else { return }
        currentThread = nil
        currentAnchor = nil
        messages = []
    }

    private func reloadThreads() {
        allThreads = (try? workspace.database.threads(documentID: workspace.document.id)) ?? []
        pageChanged(currentPage)
    }

    // MARK: Actions

    /// Starts a new thread about the selection. An answer that is running stops first.
    public func start(action: ReadingAction, question: String?, locator: PDFLocator, selectedText: String) {
        if isRunning { stop() }
        // A long selection (for example, the whole book) is cut first, so nothing below gets slow.
        let clipped = String(selectedText.prefix(ContextBuilder.selectionLimit))
        let selection = SelectionContext.make(locator: locator, selectedText: clipped, source: source, outline: outline)
        guard !selection.text.isEmpty else { return }
        let now = Date()
        let anchor = AnchorRecord(
            id: UUID().uuidString, documentID: workspace.document.id, kind: DocumentKind.pdf.rawValue,
            locatorJSON: (try? locator.json()) ?? "{\"segments\":[]}", text: selection.text,
            structuralPath: selection.structuralPath.joined(separator: " › "), firstPage: locator.firstPage, createdAt: now)
        let thread = ThreadRecord(id: UUID().uuidString, documentID: workspace.document.id, anchorID: anchor.id,
                                  title: String(selection.text.prefix(80)), firstPage: locator.firstPage,
                                  createdAt: now, updatedAt: now, agentID: selectedAgentID, modelID: selectedModel)
        do {
            try workspace.database.createThread(thread, anchor: anchor)
        } catch {
            errorMessage = "Reader cannot save the thread: \(error.localizedDescription)"
            return
        }
        currentThread = thread
        currentAnchor = anchor
        messages = []
        let visible = action == .ask ? (question ?? "") : action.title
        let context = contextSource(excluding: thread.id)
        run(userText: visible, action: action.rawValue) {
            (ContextBuilder.firstPrompt(context.input(selection, action, question)), nil)
        }
        reloadThreads()
    }

    public func followUp(_ text: String) {
        followUp(text, shownAs: nil)
    }

    /// A quick follow-up shows its short title in the thread and sends the prompt text from the templates.
    public func quick(_ followUp: QuickFollowUp) {
        self.followUp(PromptTemplates.load(from: defaults).text(for: followUp), shownAs: followUp.title)
    }

    private func followUp(_ text: String, shownAs title: String?) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isRunning, let thread = currentThread else { return }
        let selection = SelectionContext(text: currentAnchor?.text ?? thread.title, pageIndex: thread.firstPage,
                                         structuralPath: StructuralPath.path(forPage: thread.firstPage, in: outline),
                                         before: [], after: [])
        let transcript = messages.map { (role: $0.role, content: $0.text) }
        let context = contextSource(excluding: thread.id)
        run(userText: title ?? question, action: ReadingAction.followup.rawValue) {
            (question, ContextBuilder.resumePrompt(context.input(selection, .followup, question), transcript: transcript))
        }
    }

    /// Runs the last question again (for example, after an agent error). The failed question and answer are removed.
    public func retry() {
        guard !isRunning, let last = lastRun, let thread = currentThread else { return }
        if messages.last?.status == "failed" {
            let failed = messages.suffix(2).map(\.id)
            messages.removeLast(min(2, messages.count))
            try? workspace.database.deleteMessages(ids: failed, threadID: thread.id)
        }
        run(userText: last.userText, action: last.action, prompts: last.prompts)
    }

    /// Stops the answer at once. The agent gets a cancel request; the partial answer stays, marked as stopped.
    public func stop() {
        guard isRunning else { return }
        runID = nil
        runTask?.cancel()
        if let handle = runningHandle { Task { await handle.cancel() } }
        if let thread = currentThread, var answer = messages.last, answer.role == "assistant", answer.status == "streaming" {
            answer.status = "cancelled"
            replace(answer)
            save(answer, thread: thread.id)
        }
        isRunning = false
        activity = nil
        runningHandle = nil
        reloadThreads()
    }

    typealias Prompts = @Sendable () -> (first: String, resume: String?)

    /// Sends a prompt and streams the answer into a new assistant message. The prompts are made off the main
    /// thread (they search the book). `resume` is used instead of `first` when the thread has no open session.
    private func run(userText: String, action: String, prompts: @escaping Prompts) {
        guard let thread = currentThread else { return }
        errorMessage = nil
        lastRun = (userText, action, prompts)
        let user = ChatMessage(id: UUID().uuidString, role: "user", action: action, text: userText, status: "complete",
                               error: nil, createdAt: Date())
        var answer = ChatMessage(id: UUID().uuidString, role: "assistant", action: nil, text: "", status: "streaming",
                                 error: nil, createdAt: Date().addingTimeInterval(0.001))
        messages += [user, answer]
        save(user, thread: thread.id)
        save(answer, thread: thread.id)
        isRunning = true
        activity = "Starting \(selectedAgent.name)…"
        let agent = selectedAgent
        let model = selectedModel
        let id = UUID()
        runID = id

        runTask = Task { [weak self] in
            guard let self else { return }
            do {
                let built = await Task.detached(priority: .userInitiated) { prompts() }.value
                let (handle, isNew) = try await self.session(for: thread.id, agent: agent, model: model)
                guard self.runID == id else { return }
                self.runningHandle = handle
                self.activity = "\(agent.name) is thinking…"
                var lastSave = Date()
                var toolSinceText = false
                for try await event in await handle.prompt(isNew ? (built.resume ?? built.first) : built.first) {
                    guard self.runID == id else { return }
                    switch event {
                    case .text(let chunk):
                        // Text before and after a tool call are separate paragraphs.
                        if toolSinceText && !answer.text.isEmpty && !answer.text.hasSuffix("\n\n") { answer.text += "\n\n" }
                        toolSinceText = false
                        answer.text += chunk
                        self.activity = nil
                    case .tool(_, let title, _):
                        toolSinceText = true
                        if let title { self.activity = title }
                    case .thought:
                        break
                    case .done(let stopReason):
                        answer.status = stopReason == "cancelled" ? "cancelled" : "complete"
                    }
                    self.replace(answer)
                    if Date().timeIntervalSince(lastSave) > 0.5 {
                        self.save(answer, thread: thread.id)
                        lastSave = Date()
                    }
                }
                if answer.status == "streaming" { answer.status = Task.isCancelled ? "cancelled" : "complete" }
            } catch {
                guard self.runID == id else { return }
                answer.status = "failed"
                answer.error = error.localizedDescription
                self.errorMessage = error.localizedDescription
                self.sessions[thread.id] = nil
            }
            guard self.runID == id else { return }
            self.runID = nil
            self.replace(answer)
            self.save(answer, thread: thread.id)
            self.isRunning = false
            self.activity = nil
            self.runningHandle = nil
            self.reloadThreads()
        }
    }

    /// The open session of the thread, or a new one. A new session gets the chosen model; the agent's safety
    /// settings are checked again after the change.
    private func session(for threadID: String, agent: AgentSpec, model: String?) async throws -> (AgentSessionHandle, Bool) {
        if let existing = sessions[threadID], existing.agent == agent.id, existing.model == model {
            return (existing.handle, false)
        }
        let handle = try await backend.openSession(agent: agent, cwd: workspace.folder)
        var options = handle.configOptions
        if let model, let current = options.first(where: { $0.id == "model" })?.currentValue, current != model,
           options.first(where: { $0.id == "model" })?.choices.contains(where: { $0.value == model }) == true {
            options = try await handle.setOption("model", model)
            try AgentHost.verify(agent, options: options.isEmpty ? handle.configOptions : options)
        }
        let modelOption = options.first { $0.id == "model" }
        modelChoices = modelOption?.choices ?? []
        let effective = modelOption?.currentValue ?? model
        if selectedModel == nil || !modelChoices.contains(where: { $0.value == selectedModel }) { selectedModel = effective }
        // The key is the model in use, so the next question in this thread finds this session.
        sessions[threadID] = (agent.id, selectedModel, handle)
        try? workspace.database.updateThreadAgent(threadID: threadID, agentID: agent.id, modelID: effective)
        return (handle, true)
    }

    /// The data that the prompt needs, captured on the main thread, so the prompt can be made off it.
    private func contextSource(excluding threadID: String) -> PromptContextSource {
        PromptContextSource(database: workspace.database, document: workspace.document,
                            aboutMe: defaults.string(forKey: Self.aboutMeKey) ?? "", excludedThread: threadID,
                            templates: PromptTemplates.load(from: defaults))
    }

    private func replace(_ message: ChatMessage) {
        if let index = messages.firstIndex(where: { $0.id == message.id }) { messages[index] = message }
    }

    private func save(_ message: ChatMessage, thread: String) {
        try? workspace.database.saveMessage(MessageRecord(
            id: message.id, threadID: thread, role: message.role, action: message.action, content: message.text,
            status: message.status, error: message.error, createdAt: message.createdAt))
    }

    private static func chat(_ record: MessageRecord) -> ChatMessage {
        // An answer that was streaming when the app stopped is shown as stopped.
        let status = record.status == "streaming" ? "cancelled" : record.status
        return ChatMessage(id: record.id, role: record.role, action: record.action, text: record.content,
                           status: status, error: record.error, createdAt: record.createdAt)
    }
}
