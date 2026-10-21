// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import FutureTKit

/// First-run guide. FutureT installs its runtime and model by itself and asks macOS for the two permissions;
/// the only thing left for the user is the switch macOS keeps for them, and the app notices the moment it is on.
struct SetupView: View {
    let model = AppModel.shared
    var compact = false
    private var state: SetupState { model.setupState }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up FutureT").font(.system(size: compact ? 15 : 18, weight: .semibold))
                Text("Everything stays on this Mac. FutureT does the setup; macOS only needs you to switch two permissions on.")
                    .font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 0) {
                ForEach(state.items) { item in
                    step(item)
                    if item.id != state.items.last?.id { Divider() }
                }
            }.padding(.horizontal, 12).background(Theme.card, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))

            if model.missingPermission {
                Text("In System Settings, switch FutureT on in the list. This page updates by itself, and nothing needs restarting.")
                    .font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let failed = model.failedSetupMessage {
                Text(failed).font(.system(size: 12)).foregroundStyle(Theme.danger).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                Button("Copy report") { Diagnostics.copyReport() }.buttonStyle(Pill())
            }
            HStack(spacing: 10) {
                Button { model.setUpEverything() } label: {
                    HStack(spacing: 6) { if model.busy { ProgressView().controlSize(.small) }; Text(model.busy ? "Setting up…" : "Set everything up") }
                }.buttonStyle(Pill(kind: .primary)).disabled(model.busy)
                if model.busy, let t = model.runningTask { Text(t.lines.last ?? "").font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1) }
            }
        }.frame(maxWidth: 520, alignment: .leading)
    }

    private func step(_ item: Prereq) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.isMet ? "checkmark.circle.fill" : "circle").foregroundStyle(item.isMet ? Theme.ok : .secondary).font(.system(size: 15))
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).font(.system(size: 13, weight: .medium))
                Text(item.isMet ? "Ready" : item.detail).font(.system(size: 11.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if !item.isMet, case .permission(let kind) = item.install {
                Button("Open Settings") { model.request(kind) }.buttonStyle(Pill())
            } else if !item.isMet, model.busy {
                ProgressView().controlSize(.small)
            }
        }.padding(.vertical, 9)
    }
}
