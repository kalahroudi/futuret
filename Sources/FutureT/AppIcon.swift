// SPDX-License-Identifier: Apache-2.0

import AppKit

/// The app icon, drawn in code so the build needs no image tools and stays crisp at every size.
/// A violet tile with an "F" whose stem is solid and whose arms fade out: the end of a sentence being finished for you.
enum AppIcon {
    /// - padded: leave the transparent margin macOS expects around Dock icons (824 of 1024).
    static func image(size: CGFloat, padded: Bool = false) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            let s = size / 1024
            let inset: CGFloat = padded ? 100 : 0
            let tile = NSRect(x: inset * s, y: inset * s, width: (1024 - 2 * inset) * s, height: (1024 - 2 * inset) * s)
            let k = tile.width / 1024                                  // glyph units follow the tile, not the canvas
            let shape = NSBezierPath(roundedRect: tile, xRadius: tile.width * 0.2246, yRadius: tile.width * 0.2246)

            if padded, let ctx = NSGraphicsContext.current?.cgContext {   // soft Dock shadow
                ctx.saveGState()
                ctx.setShadow(offset: CGSize(width: 0, height: -10 * s), blur: 24 * s, color: NSColor.black.withAlphaComponent(0.28).cgColor)
                NSColor.black.setFill(); shape.fill()
                ctx.restoreGState()
            }
            NSGradient(starting: NSColor(srgbRed: 0.60, green: 0.45, blue: 1.0, alpha: 1), ending: NSColor(srgbRed: 0.17, green: 0.09, blue: 0.50, alpha: 1))?
                .draw(in: shape, angle: 60)
            // gentle top sheen
            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            NSGradient(starting: NSColor.white.withAlphaComponent(0.10), ending: NSColor.white.withAlphaComponent(0))?
                .draw(in: NSRect(x: tile.minX, y: tile.minY, width: tile.width, height: tile.height * 0.5), angle: 90)
            NSGraphicsContext.restoreGraphicsState()

            func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, alpha: CGFloat) {
                let r = NSRect(x: tile.minX + x * k, y: tile.minY + y * k, width: w * k, height: h * k)
                NSColor.white.withAlphaComponent(alpha).setFill()
                NSBezierPath(roundedRect: r, xRadius: min(w, h) * k * 0.5, yRadius: min(w, h) * k * 0.5).fill()
            }
            // F: solid stem, top arm slightly softer, middle arm ghosted.
            bar(360, 232, 364, 124, alpha: 0.92)
            bar(360, 452, 240, 112, alpha: 0.55)
            bar(300, 232, 124, 560, alpha: 1.0)
            bar(660, 456, 64, 104, alpha: 0.28)                        // the suggestion trailing off
            return true
        }
    }

    /// Writes an .iconset folder for `iconutil -c icns`.
    static func writeIconset(to dir: String) throws {
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let sizes: [(String, CGFloat)] = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                                          ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)]
        for (name, px) in sizes {
            guard let tiff = image(size: px, padded: true).tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            try png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("icon_\(name).png"))
        }
    }
}
