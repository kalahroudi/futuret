// SPDX-License-Identifier: Apache-2.0

import Foundation

/// How much text one suggestion may contain.
public enum CompletionLength: String, Codable, CaseIterable, Sendable {
    case word, phrase, sentence, paragraph

    public var maxTokens: Int {
        switch self { case .word: return 4; case .phrase: return 14; case .sentence: return 32; case .paragraph: return 96 }
    }
    /// Sequences that end generation. Shorter lengths stop at the first line break; paragraph stops at a blank line.
    public var stop: [String] {
        switch self { case .paragraph: return ["\n\n"]; default: return ["\n"] }
    }
    /// Stop after the first sentence end, for `.sentence`.
    public var endsAtSentence: Bool { self == .sentence }
}

/// Everything the model is told besides the text itself.
public struct CompletionContext: Equatable, Sendable {
    public var appName: String
    public var style: String            // plain-English writing instructions, may be empty
    public var phrases: [String]        // phrases this user writes often, most relevant first
    public var before: String           // text before the cursor
    public var after: String            // text after the cursor on the same line, may be empty

    public init(appName: String = "", style: String = "", phrases: [String] = [], before: String, after: String = "") {
        self.appName = appName; self.style = style; self.phrases = phrases; self.before = before; self.after = after
    }
}

/// Turns context into a prompt a base (non chat) model simply continues.
/// Stable parts come first and the user's text comes last, so the server's prompt cache keeps
/// reusing everything up to the cursor as the user types.
public enum PromptBuilder {
    public static let maxBeforeChars = 1500
    public static let maxPhrases = 6

    public static func build(_ c: CompletionContext) -> String {
        var header = "Text written by the user"
        if !c.appName.isEmpty { header += " in \(c.appName)" }
        header += "."
        if !c.style.isEmpty { header += " Style: \(c.style.trimmingCharacters(in: .whitespacesAndNewlines))" }
        var lines = [header]
        let phrases = c.phrases.prefix(maxPhrases).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !phrases.isEmpty { lines.append("Lines they often write: " + phrases.map { "“\($0)”" }.joined(separator: " ")) }
        let tail = trimToWordBoundary(String(c.before.suffix(maxBeforeChars)), droppedPrefix: c.before.count > maxBeforeChars)
        lines.append("---")
        return lines.joined(separator: "\n") + "\n" + tail
    }

    /// When the text was cut at the front, drop the partial first word so the model never sees a fragment.
    static func trimToWordBoundary(_ s: String, droppedPrefix: Bool) -> String {
        guard droppedPrefix, let i = s.firstIndex(where: { $0 == " " || $0 == "\n" }) else { return s }
        return String(s[s.index(after: i)...])
    }
}

/// Cleans what the model returned so only a usable continuation is shown.
public enum SuggestionCleaner {
    /// - Parameters:
    ///   - raw: the model's text
    ///   - before: text before the cursor, used to avoid repeating it
    ///   - length: the requested length
    ///   - truncated: the model stopped because it hit the token limit, so the last word may be cut
    public static func clean(_ raw: String, before: String, length: CompletionLength, truncated: Bool) -> String? {
        var s = raw
        // Never start with a line break: the suggestion lives on the user's current line.
        while s.first == "\n" || s.first == "\r" { s.removeFirst() }
        if let nl = s.firstIndex(of: "\n"), length != .paragraph { s = String(s[..<nl]) }
        if length.endsAtSentence, let end = s.firstIndex(where: { ".!?".contains($0) }) {
            s = String(s[...end])
        }
        if truncated, length != .word, let sp = s.lastIndex(of: " ") { s = String(s[..<sp]) }
        s = s.replacingOccurrences(of: "\u{FFFD}", with: "")
        // Space handling: don't double a space the user already typed, don't glue words together.
        if before.last == " " || before.last == "\n" { while s.first == " " { s.removeFirst() } }
        let trimmedTail = s.reversed().drop(while: { $0 == " " })
        s = String(trimmedTail.reversed())
        guard !s.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        // Repeating the last few words the user just typed is not a completion.
        let lastWords = before.split(separator: " ").suffix(3).joined(separator: " ")
        if lastWords.count > 6, s.hasPrefix(lastWords) { return nil }
        return s
    }
}
