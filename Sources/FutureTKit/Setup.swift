// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The two privacy permissions macOS only lets the user switch on. The app triggers the system prompt (which also
/// lists the app in System Settings), opens the right pane and notices the grant by itself.
public enum PermissionKind: String, Equatable, Sendable {
    case accessibility, inputMonitoring
}

/// One thing the app needs before it is useful. The setup screen renders these as a checklist and does everything
/// it can by itself; the only manual part is the switch macOS keeps for the user.
public struct Prereq: Identifiable, Equatable, Sendable {
    public enum Install: Equatable, Sendable {
        case automatic                  // the app downloads and installs it
        case permission(PermissionKind) // the app asks, opens the pane and waits for the switch
    }
    public let id: String
    public let title: String
    public let detail: String           // why it is needed, in one plain sentence
    public let install: Install
    public var isMet: Bool

    public init(id: String, title: String, detail: String, install: Install, isMet: Bool) {
        self.id = id; self.title = title; self.detail = detail; self.install = install; self.isMet = isMet
    }
}

public struct SetupState: Equatable, Sendable {
    public var items: [Prereq]
    public init(items: [Prereq]) { self.items = items }

    /// Runtime and model. Permissions belong to the running app (a helper process has its own), so the app appends them.
    public static func detect(modelRepo: String, paths: AppPaths = AppPaths()) -> SetupState {
        let installer = Installer(paths: paths)
        let model = ModelCatalog.all.first { $0.repo == modelRepo }
        return SetupState(items: [
            Prereq(id: "runtime", title: "Model runtime", detail: "A private Python and MLX, installed inside FutureT's own folder.",
                   install: .automatic, isMet: installer.runtimeInstalled),
            Prereq(id: "model", title: "Writing model",
                   detail: model.map { "\($0.title), downloaded once and run on this Mac." } ?? "Downloaded once and run on this Mac.",
                   install: .automatic, isMet: installer.modelInstalled(modelRepo)),
        ])
    }

    public var missing: [Prereq] { items.filter { !$0.isMet } }
    public var ready: Bool { missing.isEmpty }
    public var needsInstall: Bool { missing.contains { $0.install == .automatic } }
}
