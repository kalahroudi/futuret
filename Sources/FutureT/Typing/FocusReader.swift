// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices

/// What the focused text field looks like right now.
struct FocusSnapshot: Equatable {
    var pid: pid_t
    var bundleID: String?
    var appName: String?
    var role: String?
    var subrole: String?
    var isEditable: Bool
    var before: String          // text before the cursor, bounded
    var afterOnLine: String     // text after the cursor on the same line, bounded
    var hasSelection: Bool
    var caretRect: CGRect?      // Accessibility coordinates (top left origin)
    var fieldFrame: CGRect?
}

/// Reads the focused field through the Accessibility API. Apps differ a lot, so every read can fail and the caller falls back.
/// Called on the main actor only; a short messaging timeout keeps a hung app from freezing FutureT.
@MainActor
enum FocusReader {
    static let maxBefore = 1500
    static let maxAfter = 200
    private static var enhanced = Set<pid_t>()

    static func read() -> FocusSnapshot? {
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 0.25)
        enableWebAccessibility(appElement, pid: app.processIdentifier)

        guard let focused: AXUIElement = copy(appElement, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(focused, 0.25)
        let role: String? = copy(focused, kAXRoleAttribute)
        let subrole: String? = copy(focused, kAXSubroleAttribute)
        let editable = isEditable(focused, role: role)

        var snap = FocusSnapshot(pid: app.processIdentifier, bundleID: app.bundleIdentifier, appName: app.localizedName,
                                 role: role, subrole: subrole, isEditable: editable, before: "", afterOnLine: "",
                                 hasSelection: false, caretRect: nil, fieldFrame: frame(of: focused))
        guard editable, subrole != "AXSecureTextField", role != "AXSecureTextField" else { return snap }

        guard let range = selectedRange(focused) else { return snap }
        snap.hasSelection = range.length > 0
        let beforeStart = max(0, range.location - maxBefore)
        snap.before = string(focused, CFRange(location: beforeStart, length: range.location - beforeStart)) ?? ""
        let after = string(focused, CFRange(location: range.location + range.length, length: maxAfter)) ?? ""
        snap.afterOnLine = after.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        snap.caretRect = caretRect(focused, location: range.location, field: snap.fieldFrame)
        return snap
    }

    /// For `--probe`: the three candidate caret rectangles side by side.
    static func boundsReport() -> String {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let el: AXUIElement = copy(AXUIElementCreateApplication(app.processIdentifier), kAXFocusedUIElementAttribute),
              let r = selectedRange(el) else { return "no range" }
        let loc = r.location
        func d(_ x: CGRect?) -> String { x.map { "(\($0.minX), \($0.minY), \($0.width)x\($0.height))" } ?? "nil" }
        return "loc=\(loc) zero=\(d(bounds(el, CFRange(location: loc, length: 0)))) prev=\(d(bounds(el, CFRange(location: max(0, loc - 1), length: 1)))) next=\(d(bounds(el, CFRange(location: loc, length: 1))))"
    }

    // MARK: Attribute helpers

    private static func copy<T>(_ el: AXUIElement, _ attr: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success, let v = value else { return nil }
        return v as? T
    }

    private static func isEditable(_ el: AXUIElement, role: String?) -> Bool {
        if let settable = settable(el, kAXValueAttribute), settable { return true }
        return ["AXTextField", "AXTextArea", "AXComboBox"].contains(role ?? "")
    }

    private static func settable(_ el: AXUIElement, _ attr: String) -> Bool? {
        var s: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(el, attr as CFString, &s) == .success ? s.boolValue : nil
    }

    private static func selectedRange(_ el: AXUIElement) -> CFRange? {
        guard let v: AXValue = copy(el, kAXSelectedTextRangeAttribute) else { return nil }
        var r = CFRange()
        return AXValueGetValue(v, .cfRange, &r) ? r : nil
    }

    private static func string(_ el: AXUIElement, _ range: CFRange) -> String? {
        guard range.length > 0 else { return "" }
        var r = range
        guard let arg = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXStringForRangeParameterizedAttribute as CFString, arg, &out) == .success else { return nil }
        return out as? String
    }

    static func bounds(_ el: AXUIElement, _ range: CFRange) -> CGRect? {
        var r = range
        guard let arg = AXValueCreate(.cfRange, &r) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(el, kAXBoundsForRangeParameterizedAttribute as CFString, arg, &out) == .success,
              let v = out, CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(v as! AXValue, .cgRect, &rect) ? rect : nil
    }

    /// The caret rectangle. The edge of a neighbouring character is the most reliable answer: TextEdit (and others)
    /// report a zero-length range one line too high. Order: the right edge of the character before the cursor, the left
    /// edge of the one after it (start of a line), then the zero-length range, shifted down when it lands above the field.
    private static func caretRect(_ el: AXUIElement, location: Int, field: CGRect?) -> CGRect? {
        if location > 0, string(el, CFRange(location: location - 1, length: 1)) != "\n",
           let r = bounds(el, CFRange(location: location - 1, length: 1)), r.height > 0, r.width > 0 {
            return CGRect(x: r.maxX, y: r.minY, width: 1, height: r.height)
        }
        if let next = string(el, CFRange(location: location, length: 1)), !next.isEmpty, next != "\n",
           let r = bounds(el, CFRange(location: location, length: 1)), r.height > 0, r.width > 0 {
            return CGRect(x: r.minX, y: r.minY, width: 1, height: r.height)
        }
        guard var r = bounds(el, CFRange(location: location, length: 0)), r.height > 0, r.width < 50 else { return nil }
        if let field, r.maxY <= field.minY + 2 { r.origin.y += r.height }      // a caret cannot sit above its own field
        return r
    }

    private static func frame(of el: AXUIElement) -> CGRect? {
        guard let pos: AXValue = copy(el, kAXPositionAttribute), let size: AXValue = copy(el, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        guard AXValueGetValue(pos, .cgPoint, &p), AXValueGetValue(size, .cgSize, &s) else { return nil }
        return CGRect(origin: p, size: s)
    }

    /// Chromium and Electron apps only build their accessibility tree when asked.
    private static func enableWebAccessibility(_ app: AXUIElement, pid: pid_t) {
        guard !enhanced.contains(pid) else { return }
        enhanced.insert(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
    }
}
