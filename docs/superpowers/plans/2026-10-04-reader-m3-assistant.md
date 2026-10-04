# Reader M3 (Assistant) Implementation Record

**Goal:** Select text, press Explain, Simplify, Define or Ask, and read a streamed answer from Claude or OpenCode in a side panel. The answer uses the book context and earlier questions. Threads are saved in the workspace.

**Spec:** `docs/superpowers/specs/2026-10-03-reader-design.md`, Sections 4.2–4.4, 4.7, 5, 6. This milestone joins the spec's M3 (agents) and the main parts of M4 (context, threads, model picker), because the user asked for the core feature first. Takeaways, margin markers and the Study window come later.

**Execution:** The user said "don't ask me again… review it, merge to master… keep building". This record replaces the full plan document. Each task still uses test-first development, and a fresh reviewer checks the branch at the end.

## Facts from probes (2026-10-04)

| Topic | Claude (`npx -y @agentclientprotocol/claude-agent-acp`, v0.85.1) | OpenCode (`opencode acp`, v1.18.26) |
|---|---|---|
| Login | The Claude subscription of the user (Claude Team). No API key. | No credentials on this Mac. Only free "Zen" models. These fail often. |
| Safety | Permission requests are not reliable: the user's settings let Bash run with no request. Use `session/new` `_meta.claudeCode.options = {tools: [Read, Glob, Grep, WebSearch, WebFetch], strictMcpConfig: true, disallowedTools: [Bash, Edit, Write, MultiEdit, NotebookEdit, Agent, Task]}`. Verified: only 5 tools, no account connectors. | A changed tool set makes the free tier refuse ("can only be used from within OpenCode"). Use `session/set_config_option {configId: "mode", value: "plan"}` (read-only, verified), and refuse all permission requests. |
| Models | `configOptions` id `model`: default, opus, sonnet, haiku, … | `configOptions` id `model`: free Zen models |
| Model change | `session/set_config_option {sessionId, configId: "model", value}` | same |
| Text | `session/update` with `sessionUpdate: agent_message_chunk`, `content.text` | same |
| Errors | JSON-RPC error with `message` | same |
| Output noise | — | Terminal escape codes can come before a JSON message on the same line. Parse from the first `{`. |

## Tasks

1. **AgentKit: JSON value and JSON-RPC connection.** A `JSONValue` type (Codable, Sendable). A connection actor over a line transport: requests with IDs, responses, notifications, and replies to agent requests (refuse permission, refuse fs and terminal). Line cleanup before the first `{`. Tests with an in-memory transport.
2. **AgentKit: ACP client and process transport.** initialize, session/new with `_meta`, set_config_option, prompt as an `AsyncThrowingStream` of events (text, tool status, done), cancel. A process transport with the login-shell `PATH`. Tests with a scripted fake agent.
3. **AgentKit: agent catalog and detection.** Claude, OpenCode (supported). Gemini CLI, Codex, Cursor (detected; shown as "not supported yet"). Detection from the login-shell `PATH` and common folders. Tests with a fake `PATH` folder.
4. **WorkspaceStore: threads and messages.** Migration v3: `thread`, `message`, `thread_text` FTS5. Add, list by document and by page, append and update messages, search related threads.
5. **Assistant module: context builder.** Prompt parts from spec 5.2 with size limits: role and rules, About me, book data and location, selection with text before and after, up to 3 related threads, up to 4 related passages, tool note. Golden tests.
6. **Assistant module: assistant model.** One per reader window. Runs an action on a selection, streams the answer, saves messages, follow-ups, stop, change of agent and model, errors. Tests with a fake agent.
7. **ReaderUI: side panel and actions.** Selection bar with Explain (E), Simplify (S), Define (D), Ask (A), Highlight (H); keys work through the key monitor. Inspector panel with agent and model pickers, quote, streamed Markdown answer (native block renderer; `[p. N]` links go to the page), quick follow-ups, Stop, follow-up field, "Earlier on this page". Settings window with About me. UI tests through real event routing.
8. **Real-app self-test and live check.** The self-test presses E on a paragraph of the real book and waits for the answer from Claude. Then a screenshot check.
