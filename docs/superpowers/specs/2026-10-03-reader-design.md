# Reader: Design Specification (Version 1)

- Date: 2026-10-03
- Status: Draft for review
- License: MIT

## 1. Purpose

Reader is a macOS application. It helps a person read difficult PDFs, such as technical books and research papers, paragraph by paragraph.

When the reader does not understand a part of the text, the reader selects it and asks an LLM agent for help. The app keeps all questions and answers for each document in a **workspace**. The agent uses this workspace as memory.

The app uses the LLM subscriptions that the user already has (for example, Claude Code or OpenCode). The app does not use API keys.

### 1.1 Success criteria

1. The reader gets an explanation of a selected paragraph with one click or one key.
2. Each explanation uses the book context and the earlier questions of the reader.
3. The reader can review all earlier threads in a large, separate window.
4. The reader can select the agent and the model.
5. Other people can download the app from GitHub and use it with their own subscriptions.

### 1.2 Scope of version 1

In scope:

- PDF reader: outline, search, highlights, and reopen at the last page.
- Selection actions: Explain, Simplify, Define, Ask, and Highlight.
- Side panel chat with streaming answers.
- Study window: a full-screen library of all threads.
- Workspace memory: threads, anchors, takeaways, and a full-text index of the document.
- Agent catalog with automatic detection. OpenCode and Claude Code must work. Gemini CLI, Codex, and Cursor show when they are installed and have ACP support.
- Model picker.
- Distribution on GitHub.

Out of scope for version 1 (planned for later versions):

- Find resources (YouTube videos and blogs). Planned for version 1.1.
- Glossary and chapter brief.
- Excalidraw canvas window for diagrams.
- Markdown and code workspaces (an IDE-like mode).
- Embeddings and vector search.
- Signed and notarized builds, Homebrew cask, and automatic updates.

The design must not block the later features. Section 3 tells how.

## 2. Decisions

| Topic | Decision | Reason |
|---|---|---|
| Platform | Swift 6, SwiftUI, AppKit where PDFKit needs it, macOS 15 or later | Native PDF support and native feel |
| Storage | SQLite through GRDB, with FTS5 | Full-text search and fast queries. GRDB is the only third-party dependency. |
| LLM access | The agent CLIs of the user, through the Agent Client Protocol (ACP) | Uses the existing subscriptions. One protocol for many agents. |
| API keys | Not used | Cost control. The subscription is a fixed cost. |
| Omnigent | Not used as a dependency | It is large and in alpha. We copy its pattern (drive vendor CLIs through their machine interfaces). |
| App Sandbox | Off | The sandbox blocks the start of CLIs from the user `PATH`. Thus the app cannot go to the Mac App Store. |
| License | MIT | Simple and permissive |

## 3. Architecture

### 3.1 Main concepts

These concepts do not depend on the document type. This lets the app support Markdown files and codebases later.

- **Workspace.** A collection of one or more documents, plus the threads about them. In version 1, when the user opens a PDF, the app makes a workspace with that one PDF.
- **Document.** A source that the app can show and get text from. Version 1 has one type: `PDFDocumentSource`. Later types: `MarkdownSource`, `CodeFileSource`.
- **Anchor.** A stable pointer to a location in a document. A PDF anchor has the page index, the character range, and the highlight rectangles. Later anchors can point to a file and line range, or to a code symbol.
- **Selection context.** The data that the reader gives to the LLM:
  - the selected text,
  - the text before and after the selection,
  - the structural path (for a PDF: chapter and section; for code, later: file, type, and function).
- **Thread.** A conversation that is linked to one or more anchors.
- **Takeaway.** A summary of a thread in one or two sentences.

### 3.2 Document identity

The app identifies a PDF by the SHA-256 hash of its contents. If the user moves or renames the file, the app still finds its workspace. The workspace also stores the last known file path.

### 3.3 Modules

All modules are in one Swift package. Each module has one job.

| Module | Job |
|---|---|
| `DocumentKit` | The Document and Anchor protocols and their PDF versions. Text extraction, paragraph detection, and outline. |
| `WorkspaceStore` | One SQLite database for each workspace. Threads, messages, anchors, highlights, takeaways, and the FTS5 index of the document text. |
| `ContextBuilder` | Makes the prompt from the selection context, related threads, and related document passages. |
| `AgentKit` | ACP client over stdio, agent catalog, detection, and process management. |
| `ReaderUI` | Reader window, selection menu, side panel, and margin markers. |
| `StudyUI` | Study window. |
| `App` | App shell, windows, settings, and first-run screen. |

The UI modules only show data and send user actions. They contain no business logic.

### 3.4 Files on disk

```
~/Library/Application Support/Reader/
  agents.json                  # custom agents (optional)
  settings.json                # "About me" text, defaults
  workspaces/<workspace-id>/
    workspace.sqlite
    opencode.json              # denies edit and bash for OpenCode
    text/
      01-<chapter-slug>.md     # document text, one file for each chapter
      ...
```

The agent runs with this workspace folder as its working directory. It can read the `text/` files to find other parts of the book. The original PDF folder is never the working directory of the agent.

If the PDF has no outline, the app writes one text file for each 20 pages.

## 4. Reading flow and UI

### 4.1 Selection

- Drag to select text, as in any PDF reader.
- Option-click a paragraph to select the full paragraph.
- Option-click again to add the next paragraph to the selection.

### 4.2 Actions

A small menu shows above each selection. Each action also has a key.

| Action | Key | Result |
|---|---|---|
| Explain | `E` | Explanation in the context of the book and the chapter |
| Simplify | `S` | The same idea in simpler words, with an example |
| Define | `D` | Short definitions of the terms in the selection |
| Ask… | `A` | The user types a question about the selection |
| Highlight | `H` | Keeps a highlight. No LLM call. |

### 4.3 Side panel

- Opens on the right side of the reader window when the user starts an action. `⌘⌥0` collapses and expands it.
- The top of the panel shows the selected text as a quote, with a link to its page.
- The answer streams in.
- Under each answer, quick buttons send common follow-ups: *Simpler*, *Give an example*, *Why does this matter?*, *Connect to earlier*.
- The panel header has the agent and model picker. The app keeps the last choice for each workspace.
- Tool activity of the agent shows as short status lines, for example "Reading chapter 3".
- A **Stop** button cancels the request.

### 4.4 Thread rules

- If the new selection overlaps the anchor of an existing thread, the app opens that thread.
- If not, the app starts a new thread.
- Under the current thread, the panel shows a list named **Earlier on this page**. It contains the threads for the visible pages.

### 4.5 Margin markers

Each paragraph that has a thread gets a small dot in the page margin. A click on the dot opens the thread.

### 4.6 Study window

- Opens only when the user asks for it (`⌘⇧L` or a toolbar button). It can go full screen.
- Left side: all threads, grouped by chapter, with their takeaways and a search field.
- Right side: the selected thread, in a wide layout with large text.
- Each thread has a **Show in PDF** button. This button moves the reader window to the anchor.
- The user can continue a chat in this window. Both windows use the same store, so changes show in both windows at the same time.

### 4.7 Answer format

Answers are Markdown with code blocks, tables, and LaTeX math. The app renders them in a web view with a Markdown renderer and KaTeX. Page citations such as `[p. 142]` become links that open that page.

### 4.8 Reader basics

- Outline sidebar.
- Text search in the document.
- The app reopens each document at the last page that the user read.

### 4.9 Future windows

The window design must allow more windows that show the same workspace data. The first planned one is the Canvas window. It will show Excalidraw in a web view, and it will store each diagram as Excalidraw JSON in the workspace, linked to its source anchors.

## 5. Context and memory

### 5.1 Main rule

The app owns the memory. The agent session is only a temporary cache. Thus the user can change the agent or the model in the middle of a thread, and the new agent gets the same context.

### 5.2 Prompt for a new thread

| # | Part | Source | Size limit |
|---|---|---|---|
| 1 | Role and rules: reading tutor, explain in the context of this book, cite pages as `[p. N]` | Template file that the user can edit | small |
| 2 | About me: the background of the user | Settings | 500 tokens |
| 3 | Document data: title, author, structural path, page | PDF metadata and outline | small |
| 4 | The selection, about two paragraphs before it, and one paragraph after it | `DocumentKit` | 1,500 tokens |
| 5 | Related earlier threads: maximum 3, each with its question and takeaway | FTS5 search on threads, with the terms of the selection | 2,000 tokens |
| 6 | Related document passages: maximum 4, each with its page number | FTS5 search on the document text | 2,500 tokens |
| 7 | Tool note: the full text is in `text/`, and the agent can read it | Fixed text | small |

`ContextBuilder` cuts each part to its limit. The total for a new thread is about 6,000 to 8,000 tokens.

### 5.3 Follow-up messages

- If the agent session is still active, the app sends only the new message.
- If the session is not available (app restart, agent restart, or a change of agent or model), the app makes a new session. It sends parts 1 to 4, plus a summary of the thread messages, plus the new message.

### 5.4 Takeaways

When a thread has no new messages for 5 minutes, the app asks the agent for a takeaway of one or two sentences. The app stores it with the thread. Part 5 of the prompt and the Study window use the takeaways. This keeps the memory small when the workspace grows.

If the request for a takeaway fails, the app tries again the next time that the thread becomes inactive.

## 6. Agent integration

### 6.1 Protocol

The app is an ACP client. It sends JSON-RPC messages on the stdio of each agent process.

| Step | ACP method | When |
|---|---|---|
| 1 | `initialize` | One time for each process. The client tells the agent its capabilities. |
| 2 | `session/new` | One time for each thread. The `cwd` is the workspace folder. |
| 3 | `session/prompt` | For each message |
| 4 | `session/update` (from the agent) | Text chunks and tool calls. The app streams them to the UI. |
| 5 | `session/request_permission` (from the agent) | See Section 6.5. |
| 6 | `session/cancel` | When the user clicks Stop |

### 6.2 Agent catalog

The app contains a catalog of well-known agents as data. Each entry has: an ID, a display name, the binary name, the ACP start command, an optional adapter package, the login command, and an install guide link.

| Agent | Binary | ACP start command |
|---|---|---|
| OpenCode | `opencode` | `opencode acp` |
| Claude Code | `claude` | Zed's Claude Code ACP adapter (npm package) |
| Gemini CLI | `gemini` | The ACP flag of the Gemini CLI |
| Codex | `codex` | Zed's Codex ACP adapter (npm package) |
| Cursor | `cursor-agent` | Its ACP mode, if one is available |

The implementation plan must verify each command and package name before the code uses it.

The user can add a custom agent with one entry in `agents.json`.

### 6.3 Detection

1. A Mac app that starts from Finder does not get the shell `PATH` of the user. The app gets the `PATH` from the login shell of the user one time at start.
2. The app also looks in these folders: `/opt/homebrew/bin`, `/usr/local/bin`, `~/.local/bin`, `~/.opencode/bin`, and the npm global folder.
3. Each agent gets one of these statuses:

| Status | Meaning | What the app shows |
|---|---|---|
| Ready | The agent can start an ACP session | The agent in the model picker |
| Needs login | The binary is installed, but the agent is not logged in | The login command |
| Needs adapter | The binary is installed, but the ACP adapter is not | The npm install command. Node.js is necessary. |
| Not supported yet | The binary is installed, but it has no ACP mode | A note |
| Not installed | The binary is not found | The install guide link |

4. The app checks again when it becomes active and when the user clicks **Rescan** in Settings.
5. Only agents with the status **Ready** show in the model picker.

### 6.4 Model picker

The app shows the models that the agent reports for the session. If the agent does not report models, the app uses the model list from the catalog entry.

### 6.5 Safety

The agents are coding agents. They can edit files and run commands. The app uses three layers of protection:

1. **Client capabilities.** The app does not offer file write or terminal capabilities to the agent.
2. **Permission requests.** The app answers automatically. It allows read, search, web search, and web fetch. It refuses edit, write, and shell commands. The app does not show a dialog.
3. **Agent configuration.** The workspace folder contains an `opencode.json` that denies `edit` and `bash`. The Claude Code adapter starts with these tools disallowed. Other agents use their equivalent settings where they have them.

### 6.6 Processes

- The app keeps one process for each agent type. One process serves many sessions.
- The app starts a process at the first request for that agent.
- The app stops a process after 10 minutes with no activity.
- The app stops all agent processes when it quits.

### 6.7 Errors

| Problem | What the app does |
|---|---|
| The agent is not installed | Shows the install guide link |
| The agent is not logged in | Shows the login command |
| A rate limit or usage limit is reached | Shows the message and offers to try again with another Ready agent |
| The process stops unexpectedly | Restarts it one time and rebuilds the session from the store (Section 5.3) |
| No response for 120 seconds | Cancels the request and shows "Try again" |

The app saves partial answers while they stream. If the app or the agent stops, the user does not lose text.

## 7. Data model

All tables are in `workspace.sqlite`.

| Table | Main columns |
|---|---|
| `document` | `id`, `kind` (`pdf`), `content_hash`, `last_path`, `title`, `author`, `page_count`, `last_page` |
| `anchor` | `id`, `document_id`, `kind`, `locator_json`, `text`, `structural_path` |
| `highlight` | `id`, `anchor_id`, `color`, `created_at` |
| `thread` | `id`, `title`, `takeaway`, `created_at`, `updated_at`, `last_agent_id`, `last_model_id` |
| `thread_anchor` | `thread_id`, `anchor_id` |
| `message` | `id`, `thread_id`, `role`, `content`, `action`, `agent_id`, `model_id`, `status` (`streaming`, `complete`, `failed`, `cancelled`), `created_at` |
| `document_text` (FTS5) | `document_id`, `page_index`, `paragraph_index`, `text` |
| `thread_text` (FTS5) | `thread_id`, `text` (questions and takeaway) |

`locator_json` holds the type-specific location. For a PDF: page index, character range, and rectangles. This field lets later document types use the same table.

A global index at `~/Library/Application Support/Reader/index.sqlite` maps each `content_hash` to its workspace ID and holds the recent documents list.

## 8. Testing

| Layer | What to test | How |
|---|---|---|
| `DocumentKit` | Text extraction, paragraph detection, outline, and anchor round-trip | Unit tests with fixture PDFs: a book page, a two-column paper, and a page with math |
| `WorkspaceStore` | Migrations, FTS5 search, and thread and anchor queries | Unit tests on a temporary database |
| `ContextBuilder` | Contents and order of the prompt parts, and the size limits | Golden-file tests |
| `AgentKit` | Streaming, cancel, refused permissions, restart, timeout, and detection statuses | A fake ACP agent (a script that replays JSON-RPC from a file), and a fake `PATH` folder |
| Real agents | One Explain round-trip with OpenCode and with Claude Code | Integration tests that the developer starts manually. CI does not run them. |
| UI | Open a PDF, select text, Explain, see the answer | A small number of XCUITest smoke tests, and a manual checklist |

### 8.1 Performance targets

For a PDF with 636 pages:

- The first page shows in less than 2 seconds.
- Text extraction and indexing run in the background and show progress. The user can read while they run.

## 9. Risks

| Risk | Mitigation |
|---|---|
| Paragraph detection in PDFs is not exact. PDFKit gives lines, not paragraphs. Two columns and math make it harder. | Rules based on line spacing, indents, and columns. Test with a book and an arXiv paper. Manual selection always works. |
| ACP adapters are new and change frequently | Tests with the fake agent. Commands are data in the catalog, so a fix is a small change. |
| Subscription usage limits | The user can continue with another Ready agent. |
| Vendor terms for subscription use | The app never reads, stores, or sends credentials. Each user logs in through the vendor CLI. The README tells users to obey the terms of each vendor. |

## 10. Distribution

| Topic | Decision |
|---|---|
| Source | Public GitHub repository, MIT license |
| Credentials | The app never reads, stores, or sends tokens |
| Privacy | No telemetry. All data stays on the Mac of the user. |
| First-run screen | Shows the agent statuses and the steps to make one agent Ready |
| CI | GitHub Actions builds the app and runs the tests on each push |
| Releases | Unsigned `.dmg` on GitHub Releases. The README tells how to open it (right-click, then Open) and how to build from source. |
| Later | Developer ID signing and notarization, then a Homebrew cask |

## 11. Milestones

Each milestone gives a version that the user can use.

| # | Milestone | Result |
|---|---|---|
| M1 | Reader shell | Open a PDF, outline, search, reopen at the last page. The app makes the workspace, extracts the text, and builds the index. |
| M2 | Selection | Option-click paragraph selection, action menu, highlights, and saved anchors |
| M3 | Agents | ACP client, agent catalog, detection, first-run screen, and Explain with OpenCode in the side panel |
| M4 | Memory | Context builder, threads, takeaways, margin markers, Claude Code adapter, and model picker |
| M5 | Study window | Full-screen thread library, search, and Show in PDF |
| M6 | Sharing | README, MIT license, CI, and an unsigned `.dmg` on GitHub Releases |

After version 1:

- Version 1.1: Find resources (YouTube videos and blogs, grouped and cached for each chapter).
- Later: glossary, chapter brief, Excalidraw canvas window, and Markdown and code workspaces.
