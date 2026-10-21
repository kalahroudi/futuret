// SPDX-License-Identifier: Apache-2.0

import AppKit
import FutureTKit

/// A plain-text report the user can paste into a bug report: versions, permissions, what the pipeline is doing,
/// and the tail of the app and model server logs. Typed text is never included, only status and log lines.
@MainActor
enum Diagnostics {
    static func report() -> String {
        let hw = Hardware.current()
        let live = SuggestionCoordinator.shared.live
        let paths = AppPaths()
        let installer = Installer(paths: paths)
        var out = """
        FutureT \(BuildInfo.current.version) (\(BuildInfo.current.commit ?? "development build"))
        macOS \(ProcessInfo.processInfo.operatingSystemVersionString) · \(hw.chip) · \(formatBytes(hw.memoryBytes))
        Model: \(Prefs.shared.modelRepo) · runtime installed: \(installer.runtimeInstalled) · model installed: \(installer.modelInstalled(Prefs.shared.modelRepo))
        Accessibility: \(Permissions.accessibility) · Input Monitoring: \(Permissions.inputMonitoring) · key listener: \(SuggestionCoordinator.shared.isRunning)
        Status: \(live.stage)
        Server: \(live.server) · keys seen \(live.keys) · accepted \(live.accepted)
        """
        for name in ["app.log", "server.log"] {
            out += "\n\n--- \(name) (last 60 lines) ---\n" + tail(paths.logsDir.appendingPathComponent(name), lines: 60)
        }
        return out
    }

    static func copyReport() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report(), forType: .string)
        AppModel.shared.show("Report copied. Paste it into your message.")
    }

    private static func tail(_ url: URL, lines: Int) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "(no log yet)" }
        return text.split(separator: "\n", omittingEmptySubsequences: false).suffix(lines).joined(separator: "\n")
    }
}
