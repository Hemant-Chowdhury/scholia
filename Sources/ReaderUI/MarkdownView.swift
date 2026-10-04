import Foundation
import SwiftUI

/// A small Markdown block parser for agent answers. Inline styles use AttributedString.
enum MarkdownBlocks {
    enum Block: Equatable {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet(marker: String, text: String)
        case quote(String)
        case code(String)
    }

    static func parse(_ text: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var code: [String]?

        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: " "))) }
            paragraph = []
        }

        for rawLine in text.components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") {
                if let lines = code {
                    blocks.append(.code(lines.joined(separator: "\n")))
                    code = nil
                } else {
                    flush()
                    code = []
                }
                continue
            }
            if code != nil { code?.append(rawLine); continue }
            if line.isEmpty { flush(); continue }
            if let heading = line.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                flush()
                blocks.append(.heading(level: heading.1.count, text: String(heading.2)))
            } else if let bullet = line.firstMatch(of: /^[-*+]\s+(.*)$/) {
                flush()
                blocks.append(.bullet(marker: "•", text: String(bullet.1)))
            } else if let numbered = line.firstMatch(of: /^(\d+[.)])\s+(.*)$/) {
                flush()
                blocks.append(.bullet(marker: String(numbered.1).replacingOccurrences(of: ")", with: "."), text: String(numbered.2)))
            } else if let quote = line.firstMatch(of: /^>\s?(.*)$/) {
                flush()
                blocks.append(.quote(String(quote.1)))
            } else {
                paragraph.append(line)
            }
        }
        if let lines = code { blocks.append(.code(lines.joined(separator: "\n"))) }
        flush()
        return blocks
    }

    /// "[p. 12]" becomes a link that the reader view opens as page 12.
    static func linkingPages(_ text: String) -> String {
        text.replacing(/\[p\. (\d+)\](?!\()/) { match in "[p. \(match.1)](reader-page://\(match.1))" }
    }

    static func pageNumber(in url: URL) -> Int? {
        guard url.scheme == "reader-page", let host = url.host() else { return nil }
        return Int(host)
    }

    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: linkingPages(text), options: options)) ?? AttributedString(text)
    }
}

/// Shows an agent answer. `[p. N]` links open page N (through the openURL environment action).
struct MarkdownView: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .heading(let level, let content):
                    Text(MarkdownBlocks.inline(content))
                        .font(level <= 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                        .padding(.top, 4)
                case .paragraph(let content):
                    Text(MarkdownBlocks.inline(content))
                case .bullet(let marker, let content):
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker).foregroundStyle(.secondary).monospacedDigit()
                        Text(MarkdownBlocks.inline(content))
                    }
                    .padding(.leading, 4)
                case .quote(let content):
                    Text(MarkdownBlocks.inline(content))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 10)
                        .overlay(alignment: .leading) { Rectangle().fill(.tertiary).frame(width: 3) }
                case .code(let content):
                    ScrollView(.horizontal) {
                        Text(content).font(.system(.callout, design: .monospaced)).textSelection(.enabled).padding(8)
                    }
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
