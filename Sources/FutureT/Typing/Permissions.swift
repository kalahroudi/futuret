// SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import CoreGraphics

/// The two permissions macOS makes the user grant by hand. The app asks, opens the right pane and notices the moment it is granted.
enum Permissions {
    static var accessibility: Bool { AXIsProcessTrusted() }
    static var inputMonitoring: Bool { CGPreflightListenEventAccess() }
    static var all: Bool { accessibility && inputMonitoring }

    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    static func requestInputMonitoring() { _ = CGRequestListenEventAccess() }

    static func openAccessibilityPane() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    static func openInputMonitoringPane() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }
}
