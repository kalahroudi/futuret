// SPDX-License-Identifier: Apache-2.0

import Foundation
import CoreGraphics

/// One suggestion on screen and how it follows the user's typing.
/// Pure value logic, so every edge case is unit tested; the UI layer only feeds it what the field now contains.
public struct SuggestionSession: Equatable, Sendable {
    /// Text before the cursor when the suggestion was made.
    public let anchor: String
    /// What has not been typed or accepted yet.
    public private(set) var remaining: String

    public init(anchor: String, suggestion: String) {
        self.anchor = anchor
        self.remaining = suggestion
    }

    public enum Reconcile: Equatable, Sendable {
        case unchanged
        case advanced      // the user typed the start of the suggestion; the rest still applies
        case finished      // the user typed all of it
        case invalid       // the text went somewhere else (other characters, deletion, moved cursor)
    }

    /// Compares the text before the cursor now with the anchor. Typing the suggestion's own letters keeps it alive.
    public mutating func reconcile(currentBefore: String) -> Reconcile {
        if currentBefore == anchor { return .unchanged }
        guard currentBefore.hasPrefix(anchor) else { return .invalid }
        let typed = String(currentBefore.dropFirst(anchor.count))
        guard remaining.hasPrefix(typed) else { return .invalid }
        remaining = String(remaining.dropFirst(typed.count))
        self = SuggestionSession(anchor: currentBefore, suggestion: remaining)
        return remaining.isEmpty ? .finished : .advanced
    }

    /// The next word with the spaces in front of it, for word-by-word acceptance.
    public var nextWord: String { Self.firstWord(of: remaining) }

    public static func firstWord(of s: String) -> String {
        var out = ""
        var seenLetter = false
        for ch in s {
            if ch.isWhitespace {
                if seenLetter { break }
                out.append(ch)
            } else {
                seenLetter = true
                out.append(ch)
                if ch.isPunctuation && !"'’-".contains(ch) { break }   // "word," -> "word,"
            }
        }
        return out
    }

    /// Records that `chunk` was inserted into the field.
    public mutating func accepted(_ chunk: String) {
        guard remaining.hasPrefix(chunk) else { remaining = ""; return }
        remaining = String(remaining.dropFirst(chunk.count))
        self = SuggestionSession(anchor: anchor + chunk, suggestion: remaining)
    }
}

/// When to hold back a suggestion because the user is typing something a continuation would only get in the way of.
public enum ContextGuard {
    /// True for a link, an email address, an @mention, a #tag or a long number (card, phone, code).
    public static func shouldHold(before: String) -> Bool {
        let token = before.split(whereSeparator: { $0.isWhitespace }).last.map(String.init) ?? ""
        guard !token.isEmpty, before.last?.isWhitespace == false else { return false }
        let lower = token.lowercased()
        if lower.contains("://") || lower.hasPrefix("www.") || lower.hasPrefix("http") { return true }
        if token.hasPrefix("@") || token.hasPrefix("#") { return true }
        if token.contains("@") { return true }
        let digits = token.filter(\.isNumber).count
        if digits >= 6 && digits * 2 >= token.count { return true }
        return false
    }
}

/// Which fields FutureT may touch at all.
public struct FieldPolicy: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case allowed
        case blocked(String)
        public var isAllowed: Bool { self == .allowed }
    }

    /// Password managers, key chains and terminals stay off unless the user turns them on.
    public static let defaultBlockedApps: Set<String> = [
        "com.apple.keychainaccess", "com.apple.Passwords", "com.1password.1password", "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx", "com.bitwarden.desktop", "com.dashlane.dashlanephonefinal", "com.lastpass.LastPass",
        "org.keepassxc.keepassxc", "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "net.kovidgoyal.kitty",
    ]

    public var blockedApps: Set<String>
    public var disabledApps: Set<String>      // turned off by the user, per app
    public var enabled: Bool

    public init(blockedApps: Set<String> = FieldPolicy.defaultBlockedApps, disabledApps: Set<String> = [], enabled: Bool = true) {
        self.blockedApps = blockedApps; self.disabledApps = disabledApps; self.enabled = enabled
    }

    public func evaluate(bundleID: String?, role: String?, subrole: String?, isEditable: Bool) -> Verdict {
        guard enabled else { return .blocked("FutureT is paused") }
        if subrole == "AXSecureTextField" || role == "AXSecureTextField" { return .blocked("Secure field") }
        guard isEditable else { return .blocked("Not a text field") }
        if role == "AXSearchField" || subrole == "AXSearchField" { return .blocked("Search box") }
        if let id = bundleID {
            if disabledApps.contains(id) { return .blocked("Turned off for this app") }
            if blockedApps.contains(id) { return .blocked("Protected app") }
        }
        return .allowed
    }
}

/// Where the ghost text goes. Accessibility reports rectangles with the origin at the top left of the main display;
/// AppKit windows use the bottom left, so they are flipped here.
public enum CaretPlacement {
    public struct Result: Equatable, Sendable {
        public enum Style: Equatable, Sendable { case inline, card }
        public var frame: CGRect
        public var style: Style
    }

    public static func flip(_ axRect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        CGRect(x: axRect.minX, y: mainScreenHeight - axRect.maxY, width: axRect.width, height: axRect.height)
    }

    /// - Parameters:
    ///   - caret: caret rectangle in AppKit coordinates
    ///   - textWidth: width the suggestion needs on one line
    ///   - lineHeight: height of the caret line
    ///   - screen: visible frame of the screen holding the caret
    public static func place(caret: CGRect, textWidth: CGFloat, lineHeight: CGFloat, screen: CGRect, rightLimit: CGFloat? = nil, textFollows: Bool = false) -> Result {
        let edge = min(screen.maxX, rightLimit ?? screen.maxX)
        let room = edge - caret.maxX - 8
        let height = max(lineHeight, caret.height)
        let lineY = caret.minY + (caret.height - height) / 2
        // Text already sits to the right of the cursor: drawing inline would land on top of it, so use the card.
        if !textFollows, textWidth <= room {
            return Result(frame: CGRect(x: caret.maxX, y: lineY, width: textWidth, height: height), style: .inline)
        }
        // Not all of it fits on the line, but enough does: show the start, cut with an ellipsis. Accepting still inserts it all.
        if !textFollows, room >= 140 {
            return Result(frame: CGRect(x: caret.maxX, y: lineY, width: room, height: height), style: .inline)
        }
        // No room on the line: a small card below the caret, kept on screen.
        let width = min(max(textWidth, 160), 360)
        var x = caret.minX
        if x + width > screen.maxX - 8 { x = screen.maxX - width - 8 }
        x = max(x, screen.minX + 8)
        var y = caret.minY - lineHeight - 14
        if y < screen.minY + 8 { y = caret.maxY + 6 }
        return Result(frame: CGRect(x: x, y: y, width: width, height: lineHeight + 8), style: .card)
    }
}

/// How long the Tab/Esc hint chip stays.
public enum KeyHintMode: String, Codable, CaseIterable, Sendable {
    case always, untilLearned, never
    public static let learnedAfter = 10
    public func shouldShow(acceptedCount: Int) -> Bool {
        switch self { case .always: return true; case .never: return false; case .untilLearned: return acceptedCount < Self.learnedAfter }
    }
}

/// How soon a suggestion appears after the user stops typing.
public enum SuggestionTiming: String, Codable, CaseIterable, Sendable {
    case instant, balanced, pause
    public var delay: TimeInterval {
        switch self { case .instant: return 0.05; case .balanced: return 0.18; case .pause: return 0.7 }
    }
}
