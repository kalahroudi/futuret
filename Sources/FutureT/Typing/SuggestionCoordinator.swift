// SPDX-License-Identifier: Apache-2.0

import AppKit
import FutureTKit

/// Ties the pieces together: key events → read the field → ask the model → show ghost text → insert on accept.
/// Every result is checked against the current work number and the field's text before it is shown, because the
/// user keeps typing while the model thinks.
@MainActor
final class SuggestionCoordinator {
    static let shared = SuggestionCoordinator()

    private let paths = AppPaths()
    private let keyTap = KeyTap()
    private let overlay = GhostOverlay()
    private lazy var server = ModelServer(paths: paths)
    private var session: SuggestionSession?
    private var work = 0
    private var pending: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private let debug = ProcessInfo.processInfo.environment["FUTURET_DEBUG"] != nil
    private func log(_ s: @autoclosure () -> String) { if debug { FileHandle.standardError.write(Data(("[futuret] " + s() + "\n").utf8)) } }
    private(set) var lastNote = ""      // why nothing is showing, for the popover

    var isRunning: Bool { keyTap.isRunning }
    private var prefs: Prefs { Prefs.shared }

    /// Starts watching the keyboard once both permissions are granted and the model is installed.
    @discardableResult
    func start() -> Bool {
        log("start: ax=\(Permissions.accessibility) input=\(Permissions.inputMonitoring)")
        guard Permissions.all, keyTap.isRunning || keyTap.start() else { log("start failed"); return false }
        log("tap running")
        server.reapOrphan()
        keyTap.onKey = { [weak self] in Task { @MainActor in self?.typed() } }
        keyTap.onAction = { [weak self] action in Task { @MainActor in self?.perform(action) } }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        })
        return true
    }

    func stop() {
        keyTap.stop(); dismiss(); pending?.cancel(); idleTask?.cancel()
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; observers = []
        Task { await server.stop() }
    }

    /// Called while quitting: no time to wait politely.
    func shutdownNow() { keyTap.stop(); server.killNow() }

    var modelReady: Bool {
        let i = Installer(paths: paths)
        return i.runtimeInstalled && i.modelInstalled(prefs.modelRepo)
    }

    // MARK: Typing

    private func typed() {
        log("key")
        pending?.cancel()
        work += 1
        let mine = work
        pending = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(30))                  // let the host app apply the key first
            guard let self, !Task.isCancelled, mine == self.work else { return }
            if self.followTyping() { return }
            try? await Task.sleep(for: .seconds(self.prefs.timing.delay))
            guard !Task.isCancelled, mine == self.work else { return }
            await self.generate(work: mine)
        }
    }

    /// If a suggestion is showing and the user typed its first letters, keep showing the rest. True when nothing more is needed.
    private func followTyping() -> Bool {
        guard var s = session, let snap = FocusReader.read() else { dismiss(); return false }
        switch s.reconcile(currentBefore: snap.before) {
        case .unchanged: return true
        case .advanced:
            session = s
            present(snap)
            return true
        case .finished, .invalid:
            dismiss(); return false
        }
    }

    private func generate(work mine: Int) async {
        log("generate: enabled=\(prefs.suggestionsEnabled) model=\(modelReady)")
        guard prefs.suggestionsEnabled, modelReady, let snap = FocusReader.read() else { return }
        log("snap app=\(snap.bundleID ?? "?") before=\(snap.before.suffix(30).debugDescription)")
        let policy = FieldPolicy(disabledApps: Set(prefs.disabledApps), enabled: prefs.suggestionsEnabled)
        guard case .allowed = policy.evaluate(bundleID: snap.bundleID, role: snap.role, subrole: snap.subrole, isEditable: snap.isEditable) else { dismiss(); return }
        guard !snap.hasSelection, !snap.before.isEmpty, !ContextGuard.shouldHold(before: snap.before) else { dismiss(); return }

        let length: CompletionLength = snap.afterOnLine.isEmpty ? prefs.length : .phrase   // mid-line: keep it short
        let ctx = CompletionContext(appName: snap.appName ?? "", style: "", phrases: [], before: snap.before, after: snap.afterOnLine)
        do {
            try await ensureServer()
            let client = CompletionClient(port: await server.port)
            let r = try await client.complete(prompt: PromptBuilder.build(ctx), maxTokens: length.maxTokens, stop: length.stop)
            guard mine == work, !Task.isCancelled else { return }
            log("raw=\(r.text.debugDescription)")
            guard let text = SuggestionCleaner.clean(r.text, before: snap.before, length: length, truncated: r.truncated) else { return }
            // The field may have changed while the model worked.
            guard let now = FocusReader.read(), now.before == snap.before else { return }
            session = SuggestionSession(anchor: snap.before, suggestion: text)
            present(now)
            scheduleIdleUnload()
        } catch is CancellationError {
        } catch {
            lastNote = error.localizedDescription; log("error: \(error.localizedDescription)")
        }
    }

    private func ensureServer() async throws {
        if case .running = await server.state { return }
        try await server.start(repo: prefs.modelRepo)
    }

    private func scheduleIdleUnload() {
        idleTask?.cancel()
        let minutes = max(1, prefs.idleUnloadMinutes)
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(minutes * 60))
            guard !Task.isCancelled, let self else { return }
            await self.server.stop()
        }
    }

    // MARK: Showing and accepting

    private func present(_ snap: FocusSnapshot) {
        guard let s = session, !s.remaining.isEmpty else { dismiss(); return }
        let caret = snap.caretRect ?? snap.fieldFrame.map { CGRect(x: $0.minX + 8, y: $0.minY + 4, width: 1, height: 18) }
        guard let caret else { dismiss(); return }
        keyTap.suggestionVisible = true
        overlay.show(s.remaining, caretAX: caret, fontSize: max(10, min(30, caret.height / 1.25)),
                     showHint: prefs.hintMode.shouldShow(acceptedCount: prefs.acceptedCount))
    }

    func dismiss() {
        session = nil
        keyTap.suggestionVisible = false
        overlay.hide()
    }

    private func perform(_ action: KeyTap.Action) {
        guard var s = session else { return }
        switch action {
        case .dismiss:
            dismiss()
        case .acceptAll, .acceptWord:
            let chunk = action == .acceptAll ? s.remaining : s.nextWord
            guard !chunk.isEmpty else { dismiss(); return }
            TextInserter.type(chunk)
            s.accepted(chunk)
            session = s
            if action == .acceptAll || s.remaining.isEmpty { prefs.acceptedCount += 1 }
            work += 1
            let mine = work
            pending?.cancel()
            pending = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(60))
                guard let self, !Task.isCancelled, mine == self.work else { return }
                if s.remaining.isEmpty { self.dismiss(); await self.generate(work: mine) }
                else if let snap = FocusReader.read() { self.present(snap) }
            }
        }
    }
}
