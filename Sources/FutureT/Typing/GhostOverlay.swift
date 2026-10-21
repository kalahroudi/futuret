// SPDX-License-Identifier: Apache-2.0

import AppKit
import FutureTKit

/// A click-through floating panel that draws the suggestion at the cursor. It never takes focus, so typing is never interrupted.
@MainActor
final class GhostOverlay {
    private let panel: NSPanel
    private let label = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let background = NSVisualEffectView()

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        panel.isReleasedWhenClosed = false
        background.material = .popover
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 7
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        hint.font = .systemFont(ofSize: 10.5, weight: .medium)
        hint.textColor = .secondaryLabelColor
        panel.contentView = NSView()
    }

    var isVisible: Bool { panel.isVisible }

    /// - Parameters:
    ///   - caretAX: caret rectangle in Accessibility coordinates
    ///   - fontSize: approximate size of the host text, so the ghost text lines up
    func show(_ text: String, caretAX: CGRect, fieldAX: CGRect?, textFollows: Bool, fontSize: CGFloat, showHint: Bool) {
        guard let main = NSScreen.screens.first else { return }
        let caret = CaretPlacement.flip(caretAX, mainScreenHeight: main.frame.height)
        let fieldRight = fieldAX.map { CaretPlacement.flip($0, mainScreenHeight: main.frame.height).maxX - 6 }
        let screen = NSScreen.screens.first { $0.frame.intersects(caret) } ?? main

        let font = NSFont.systemFont(ofSize: fontSize)
        label.font = font
        label.stringValue = text
        label.textColor = NSColor.labelColor.withAlphaComponent(0.45)
        let textSize = label.intrinsicContentSize
        let placement = CaretPlacement.place(caret: caret, textWidth: ceil(textSize.width) + 2, lineHeight: ceil(textSize.height), screen: screen.visibleFrame,
                                           rightLimit: showHint ? fieldRight.map { $0 - 34 } : fieldRight, textFollows: textFollows)

        let content = panel.contentView!
        content.subviews.forEach { $0.removeFromSuperview() }
        var frame = placement.frame
        switch placement.style {
        case .inline:
            label.frame = CGRect(x: 0, y: (frame.height - textSize.height) / 2, width: frame.width, height: textSize.height)
            content.addSubview(label)
            if showHint {
                hint.stringValue = "Tab"
                let size = hint.intrinsicContentSize
                frame.size.width += size.width + 12
                hint.frame = CGRect(x: label.frame.maxX + 6, y: (frame.height - size.height) / 2, width: size.width, height: size.height)
                content.addSubview(hint)
            }
        case .card:
            background.frame = CGRect(origin: .zero, size: frame.size)
            content.addSubview(background)
            label.textColor = .labelColor
            label.frame = CGRect(x: 8, y: 4, width: frame.width - 16, height: textSize.height)
            label.lineBreakMode = .byTruncatingTail
            content.addSubview(label)
        }
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
    }

    func hide() { if panel.isVisible { panel.orderOut(nil) } }
}
