// SPDX-License-Identifier: Apache-2.0

import AppKit

/// The menu bar glyph: the "F" of the app icon. Always a template image so macOS tints it for light and dark bars.
/// State is carried by shape, never colour: filled = suggesting, outline = paused or idle, dashed = working.
enum StatusIcon {
    enum State { case active, idle, busy }

    private static func glyph() -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 4, y: 3)); p.line(to: NSPoint(x: 14, y: 3)); p.line(to: NSPoint(x: 14, y: 5.8))
        p.line(to: NSPoint(x: 7.2, y: 5.8)); p.line(to: NSPoint(x: 7.2, y: 8)); p.line(to: NSPoint(x: 12, y: 8))
        p.line(to: NSPoint(x: 12, y: 10.6)); p.line(to: NSPoint(x: 7.2, y: 10.6)); p.line(to: NSPoint(x: 7.2, y: 15))
        p.line(to: NSPoint(x: 4, y: 15)); p.close()
        p.lineJoinStyle = .round
        return p
    }

    static func image(_ state: State) -> NSImage {
        let img = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let g = glyph()
            NSColor.black.setFill(); NSColor.black.setStroke()
            switch state {
            case .active: g.fill()
            case .idle: g.lineWidth = 1.3; g.stroke()
            case .busy: g.lineWidth = 1.3; g.setLineDash([2.5, 1.8], count: 2, phase: 0); g.stroke()
            }
            return true
        }
        img.isTemplate = true
        return img
    }
}
