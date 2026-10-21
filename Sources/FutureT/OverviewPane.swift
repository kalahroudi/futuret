// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import FutureTKit

/// The main screen: is FutureT working, and a guided way to try it without guessing.
struct OverviewPane: View {
    let model = AppModel.shared
    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Overview", subtitle: model.updatedAt.map { "Updated \($0.formatted(date: .omitted, time: .standard))" })
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TryItCard()
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Live checks plus a three-step test. Everything shown comes from the real pipeline, so a red line says exactly what is missing.
struct TryItCard: View {
    let model = AppModel.shared
    let live = SuggestionCoordinator.shared.live
    static let sample = "Hi Sam, thanks for sending the draft over. Could we move the meeting to"

    var body: some View {
        let _ = model.setupState      // re-read the checks whenever the app refreshes them
        VStack(alignment: .leading, spacing: 12) {
            Text("Try it").font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                check("Accessibility access", Permissions.accessibility)
                check("Input Monitoring", Permissions.inputMonitoring)
                check("Key listener running", SuggestionCoordinator.shared.isRunning)
                check("\(live.server)", live.server == "Model ready", neutral: live.server != "Model ready")
            }
            Divider()
            step(1, "Open a test note in TextEdit.") {
                Button("Open TextEdit") { Self.openTestNote() }.buttonStyle(Pill())
            }
            step(2, "Type this, then stop and wait a second:") {
                HStack(spacing: 8) {
                    Text(Self.sample).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    CopyButton(text: Self.sample, label: "Copy")
                }
            }
            step(3, "Grey text appears after your cursor. Tab accepts all of it, → takes one word, Esc dismisses.") { EmptyView() }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    StatusDot(color: live.stage.hasPrefix("Error") ? Theme.danger : (live.stage.hasPrefix("Showing") ? Theme.ok : Theme.warn))
                    Text(live.stage).font(.system(size: 12.5, weight: .medium)).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                }
                Text("Keys seen \(live.keys) · accepted \(live.accepted)" + (live.lastMillis.map { " · last suggestion in \($0) ms" } ?? ""))
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Copy report") { Diagnostics.copyReport() }.buttonStyle(Pill())
                    Text("Status, versions and recent logs, for a bug report. Nothing you typed is included.").font(.system(size: 11)).foregroundStyle(.secondary)
                }.padding(.top, 4)
                if !live.lastSuggestion.isEmpty {
                    Text("Last suggestion: \(live.lastSuggestion)").font(.system(size: 11.5)).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        }.card(padding: 16)
    }

    private func check(_ title: String, _ ok: Bool, neutral: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : (neutral ? "circle.dotted" : "xmark.circle.fill"))
                .foregroundStyle(ok ? Theme.ok : (neutral ? Color.secondary : Theme.danger)).font(.system(size: 13))
            Text(title).font(.system(size: 12.5))
        }
    }

    private func step<C: View>(_ n: Int, _ text: String, @ViewBuilder _ extra: () -> C) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(n)").font(.system(size: 11, weight: .semibold)).frame(width: 20, height: 20).background(Theme.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.system(size: 12.5)).fixedSize(horizontal: false, vertical: true)
                extra()
            }
        }
    }

    /// An empty text file opened in TextEdit, so there is a plain editable field without any dialog or automation permission.
    static func openTestNote() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("FutureT test note.txt")
        if !FileManager.default.fileExists(atPath: url.path) { try? Data().write(to: url) }
        let textEdit = URL(fileURLWithPath: "/System/Applications/TextEdit.app")
        NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
    }
}

/// Plain-language help and a glossary. Every option in Settings that introduces a term gets an entry here.
struct HelpPane: View {
    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: "Help")
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What is FutureT?").font(.system(size: 14, weight: .semibold))
                    Text("Describe the app in two sentences, then list the terms it uses.").font(.system(size: 12.5)).foregroundStyle(.secondary)
                }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
