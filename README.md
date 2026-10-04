# Scholia

*Scholia* (singular: *scholion*) are the explanatory notes that scholars wrote in the margins of old manuscripts, one passage at a time. This app does the same for your PDFs.

Scholia is a PDF reader for macOS that helps you understand difficult books and papers, one paragraph at a time.

Select a paragraph that you do not understand. Then ask an AI agent on your Mac to explain it, to simplify it, to define its terms, to answer your own question, or to find videos and articles about it. The agent knows the book: it gets the text around your selection, related passages and your earlier questions, and it can read the full text of the book. Each book keeps its own questions and answers.

Scholia uses the AI agents that you already have (Claude Code or OpenCode) and their subscriptions. It does not use API keys.

## Features

- **PDF reader:** outline, search, highlights, and the book opens at the last page that you read.
- **Paragraph selection:** Option-click a paragraph to select it. Option-click it again to add the next paragraph, also across a page break.
- **Assistant actions** on the selection, from the bar above the selection or with one key:

  | Key | Action | Result |
  |---|---|---|
  | E | Explain | A full explanation in the context of the book |
  | S | Simplify | The same idea in simple words, with an example |
  | D | Define | Short definitions of the terms |
  | A | Ask… | An answer to your own question |
  | R | Resources | YouTube videos, articles and the basics to read first, found with web search |
  | H | Highlight | A yellow highlight (no agent) |

- **Side panel:** the answer streams in. Page citations such as `[p. 42]` are links. Quick follow-ups: *Simpler*, *Give an example*, *Why does this matter?*, *Connect to earlier*.
- **Study window** (⇧⌘L): all questions and answers of the book, grouped by chapter, with a search.
- **Settings:** *About me* (the assistant explains at your level), editable prompts, and the status of each agent.

## Requirements

- macOS 15 or later.
- At least one agent:
  - **Claude Code** (recommended). Install it from <https://claude.com/claude-code> and log in (run `claude` in Terminal). Scholia also needs **Node.js** for `npx`, because it starts Claude Code through the ACP adapter `@agentclientprotocol/claude-agent-acp`.
  - **OpenCode.** Install it from <https://opencode.ai>. Run `opencode auth login` to use your own model providers. Without a login, OpenCode has only free models, which are sometimes not available.

Scholia finds the agents in the `PATH` of your login shell and in the usual install folders. **Settings › Agents** shows what Scholia found.

## Install

1. Download `Scholia.dmg` from the [Releases](../../releases) page.
2. Open it, and drag **Scholia** to **Applications**.
3. The app is not notarized. The first time, right-click **Scholia** in Applications and select **Open**. If macOS still refuses, run this command in Terminal:

   ```sh
   xattr -dr com.apple.quarantine /Applications/Scholia.app
   ```

## Use

1. Open a PDF: **File › Open PDF…** (⌘O), or right-click a PDF in Finder and select **Open With › Scholia**.
2. Option-click a paragraph (or drag to select text).
3. Click **Explain** in the bar, or press **E**. The answer shows in the side panel (⌥⌘0 shows or hides it).
4. Ask follow-ups in the panel. Open **Study** (⇧⌘L) to read all your questions and answers.

## Privacy and safety

- Your books and your questions stay on your Mac. Scholia has no telemetry and no server.
- Scholia sends text to the agent that you select, and that agent sends it to its model provider (for example, Anthropic for Claude Code).
- Agents in Scholia can only read and search. For Claude Code, Scholia allows only the Read, Glob, Grep and WebSearch tools, with no MCP servers and without your own Claude Code settings. Each request to read a file outside the book's workspace folder needs a permission, and Scholia refuses it. OpenCode runs in its read-only plan mode, and Scholia refuses each permission request.
- Find resources uses web search. The search queries go to the search provider of the agent.

Scholia keeps its data in `~/Library/Application Support/Scholia/`. Each book has a workspace folder with a database (highlights, questions and answers) and a text copy of the book in `text/`.

## Build from source

You need Xcode 16 or later (Swift 6).

```sh
git clone https://github.com/Hemant-Chowdhury/scholia.git
cd scholia
swift test                 # all tests (the window tests open real windows)
scripts/make-app.sh        # builds build/Scholia.app
scripts/make-dmg.sh        # builds build/Scholia.dmg
open build/Scholia.app
```

Tests with real agents run only on request, because they use your subscription:

```sh
READER_LIVE_AGENT=claude swift test --filter LiveAgentTests
```

## Project structure

| Module | Job |
|---|---|
| `DocumentKit` | PDF text, paragraphs, outline, page anchors (`PDFLocator`) |
| `WorkspaceStore` | One SQLite database for each book (GRDB, FTS5): text index, highlights, threads |
| `AgentKit` | Agent Client Protocol client, agent catalog and detection, agent processes |
| `Assistant` | Prompts and context, the assistant model (streaming, threads, follow-ups) |
| `ReaderUI` | Scholia window, selection bar, side panel, Study window, Settings |
| `ReaderApp` | The app |

The design is in `docs/superpowers/specs/`.

## Known limitations

- Some PDFs store tightly justified lines with no space characters. PDFKit gives that text with joined words.
- A real hyphen at the end of a line, before a lowercase word, is removed ("multi-agent" becomes "multiagent").
- Gemini CLI, Codex and Cursor are detected, but not supported yet.

## License

MIT. See [LICENSE](LICENSE).
