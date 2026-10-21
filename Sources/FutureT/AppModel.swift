// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import FutureTKit
@preconcurrency import UserNotifications

struct BackgroundTask: Identifiable {
    enum State: Equatable { case running, done, failed(String) }
    let id = UUID()
    var title: String
    var state: State = .running
    var lines: [String] = []
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    var isError = false
}

/// App-wide state. Data is only refreshed while the popover or the manager window is visible, so an idle app costs nothing.
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    // Data: replace with the app's own.
    var status = "Ready"
    var updatedAt: Date?
    var loadedOnce = false

    // UI state
    var tasks: [BackgroundTask] = []
    var toast: Toast?
    var setupState = AppModel.detectSetup()

    var onStatusChange: ((StatusIcon.State) -> Void)?
    /// Set by `--snapshot` so screenshots use sample data and nothing is refreshed.
    var demo = false

    private var pollTask: Task<Void, Never>?
    private var popoverVisible = false
    private var managerVisible = false

    var settings: Prefs { Prefs.shared }
    /// True until every prerequisite is met: the app then shows the guided setup instead of empty screens.
    var needsSetup: Bool { !setupState.ready }
    var missingPermission: Bool { setupState.missing.contains { if case .permission = $0.install { true } else { false } } }
    var failedSetupMessage: String? {
        if case .failed(let m)? = tasks.last(where: { $0.title == "Setting up FutureT" })?.state { return "Setup stopped: \(m)" }
        return nil
    }
    var busy: Bool { tasks.contains { $0.state == .running } }
    var runningTask: BackgroundTask? { tasks.last { $0.state == .running } }

    // MARK: Visibility-driven polling (no timers while nothing is on screen)

    func setPopoverVisible(_ v: Bool) { popoverVisible = v; updatePolling() }
    func setManagerVisible(_ v: Bool) { managerVisible = v; updatePolling() }

    private func updatePolling() {
        let active = popoverVisible || managerVisible
        if active, pollTask == nil {
            pollTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refresh()
                    // While a permission is still missing, look every second so the checklist ticks the moment the switch is flipped.
                    let waiting = self.map { !Permissions.all && !$0.demo } ?? false
                    try? await Task.sleep(for: .seconds(waiting ? 1 : max(2, self?.settings.refreshSeconds ?? 5)))
                }
            }
        } else if !active {
            pollTask?.cancel(); pollTask = nil
        }
    }

    // MARK: Refresh

    func refresh() async {
        if demo { loadedOnce = true; return }
        setupState = Self.detectSetup()
        let seen = "ax=\(Permissions.accessibility) input=\(Permissions.inputMonitoring) tap=\(SuggestionCoordinator.shared.isRunning)"
        if seen != lastSeen { lastSeen = seen; Permissions.note(seen) }
        if Permissions.all, !SuggestionCoordinator.shared.isRunning { SuggestionCoordinator.shared.start() }   // granted just now: no restart needed
        onStatusChange?(busy ? .busy : .idle)
        loadedOnce = true; updatedAt = .now
    }

    // MARK: Background tasks

    /// Runs a long job without blocking the UI. `work` gets a logger; its lines show in the task banner.
    func runTask(_ title: String, notifyDone: Bool = true, after: (@MainActor (Bool) -> Void)? = nil,
                 _ work: @escaping @Sendable (@escaping @Sendable (String) -> Void) async throws -> Void) {
        let task = BackgroundTask(title: title)
        let id = task.id
        tasks.append(task)
        onStatusChange?(.busy)
        Task {
            let log: @Sendable (String) -> Void = { line in Task { @MainActor in
                if let i = AppModel.shared.tasks.firstIndex(where: { $0.id == id }) { AppModel.shared.tasks[i].lines.append(line) } } }
            do {
                try await work(log)
                finish(id, .done); after?(true)
                if notifyDone { notify("\(title) finished") }
            } catch {
                finish(id, .failed(error.localizedDescription)); after?(false)
                notify("\(title) failed", body: error.localizedDescription)
            }
            await refresh()
            try? await Task.sleep(for: .seconds(20))      // drop finished tasks after a while so the list stays small
            tasks.removeAll { $0.id == id && $0.state != .running }
        }
    }

    private func finish(_ id: UUID, _ state: BackgroundTask.State) {
        if let i = tasks.firstIndex(where: { $0.id == id }) { tasks[i].state = state }
        if case .failed(let m) = state { show(m, error: true) } else if let t = tasks.first(where: { $0.id == id }) { show("\(t.title) finished") }
    }

    func show(_ message: String, error: Bool = false) {
        let t = Toast(message: message, isError: error)
        toast = t
        Task { try? await Task.sleep(for: .seconds(error ? 8 : 3.5)); if toast == t { toast = nil } }
    }

    func notify(_ title: String, body: String = "") {
        guard settings.notify, Bundle.main.bundleIdentifier != nil else { return }   // a bare `swift run` binary cannot post
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent(); c.title = title; c.body = body
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil))
        }
    }

    // MARK: First-run setup: automate everything that can be, explain the rest

    /// Runtime and model from the Kit, plus the two permissions, which only the running app can check.
    static func detectSetup() -> SetupState {
        var state = SetupState.detect(modelRepo: Prefs.shared.modelRepo)
        state.items += [
            Prereq(id: "accessibility", title: "Accessibility access",
                   detail: "Lets FutureT see the text before your cursor, and nothing in password fields.",
                   install: .permission(.accessibility), isMet: Permissions.accessibility),
            Prereq(id: "input", title: "Input Monitoring",
                   detail: "Lets Tab, the right arrow and Esc accept or dismiss a suggestion.",
                   install: .permission(.inputMonitoring), isMet: Permissions.inputMonitoring),
        ]
        return state
    }

    private var askedForPermissions = false
    private var lastSeen = ""

    /// Shows the system prompts (which also list FutureT in Privacy & Security) and opens the pane for whatever is still off.
    func requestPermissions() {
        if !Permissions.accessibility { Permissions.requestAccessibility() }
        if !Permissions.inputMonitoring { Permissions.requestInputMonitoring() }
    }

    func request(_ kind: PermissionKind) {
        switch kind {
        case .accessibility: Permissions.requestAccessibility(); Permissions.openAccessibilityPane()
        case .inputMonitoring: Permissions.requestInputMonitoring(); Permissions.openInputMonitoringPane()
        }
    }

    /// Everything at once: the permission prompts straight away, and the runtime and model download in the background.
    func setUpEverything() {
        requestPermissions()
        guard setupState.needsInstall, !busy else { return }
        let repo = settings.modelRepo
        let choice = ModelCatalog.all.first { $0.repo == repo } ?? ModelCatalog.recommended(memoryBytes: ProcessInfo.processInfo.physicalMemory)
        runTask("Setting up FutureT", notifyDone: false) { log in
            try await Installer(paths: AppPaths()).run(model: choice) { event in
                if let line = event.log { log(line) }
            }
        }
    }

    /// First launch: start on our own, so nobody has to find a button.
    func beginSetupIfNeeded() {
        guard !demo, !askedForPermissions, needsSetup else { return }
        askedForPermissions = true
        setUpEverything()
    }
}
