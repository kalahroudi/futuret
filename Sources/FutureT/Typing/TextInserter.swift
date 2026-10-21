// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreGraphics

/// Types accepted text into the focused field as if the user had typed it. Works in nearly every app, including
/// ones that do not let other programs set their text directly.
enum TextInserter {
    static func type(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let units = Array(text.utf16)
        var i = 0
        while i < units.count {
            let end = min(i + 16, units.count)
            var chunk = Array(units[i..<end])
            for down in [true, false] {
                guard let e = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: down) else { continue }
                e.setIntegerValueField(.eventSourceUserData, value: futureTEventMarker)
                e.flags = []
                e.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: &chunk)
                e.post(tap: .cgSessionEventTap)
            }
            i = end
        }
    }
}
