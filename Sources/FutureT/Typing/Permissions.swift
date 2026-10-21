// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import CoreGraphics
import FutureTKit

/// The two permissions macOS makes the user grant by hand. The app asks, opens the right pane and notices the moment it is granted.
enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var inputMonitoring: Bool { CGPreflightListenEventAccess() }
    static var all: Bool { accessibility && inputMonitoring }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    /// Asks, and also makes one real attempt to listen: macOS lists an app under Input Monitoring only once it has tried,
    /// so the user finds FutureT already in the list and only has to switch it on.
    static func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let noop: CGEventTapCallBack = { _, _, event, _ in Unmanaged.passUnretained(event) }
        if let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
                                     eventsOfInterest: mask, callback: noop, userInfo: nil) { CFMachPortInvalidate(t) }
    }

    static func openAccessibilityPane() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    static func openInputMonitoringPane() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    /// Appends a line to FutureT's own log, so "is it working?" can be answered from a file.
    static func note(_ line: String) {
        let paths = AppPaths()
        try? FileManager.default.createDirectory(at: paths.logsDir, withIntermediateDirectories: true)
        let url = paths.logsDir.appendingPathComponent("app.log")
        let stamp = ISO8601DateFormatter().string(from: .now)
        guard let data = "\(stamp) \(line)\n".data(using: .utf8) else { return }
        if let h = try? FileHandle(forWritingTo: url) { defer { try? h.close() }; _ = try? h.seekToEnd(); try? h.write(contentsOf: data) }
        else { try? data.write(to: url) }
    }
}
