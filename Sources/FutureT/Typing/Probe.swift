// SPDX-License-Identifier: Apache-2.0

import AppKit
import FutureTKit

/// `FutureT --probe`: prints what FutureT can see in the focused field, five times a second apart. Used to check
/// Accessibility reading in a given app without running the whole app.
enum Probe {
    static func run() {
        print("accessibility: \(Permissions.accessibility)  input monitoring: \(Permissions.inputMonitoring)")
        for _ in 0..<5 {
            MainActor.assumeIsolated {
                if let s = FocusReader.read() {
                    let verdict = FieldPolicy().evaluate(bundleID: s.bundleID, role: s.role, subrole: s.subrole, isEditable: s.isEditable)
                    print("app=\(s.bundleID ?? "?") role=\(s.role ?? "?") editable=\(s.isEditable) verdict=\(verdict)")
                    print("  before=\(s.before.suffix(60).debugDescription) after=\(s.afterOnLine.prefix(40).debugDescription)")
                    print("  \(FocusReader.boundsReport())")
                    print("  caret=\(s.caretRect.map { "\($0)" } ?? "nil") field=\(s.fieldFrame.map { "\($0)" } ?? "nil")")
                } else { print("no focused element") }
            }
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
