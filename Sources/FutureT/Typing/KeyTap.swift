// SPDX-License-Identifier: Apache-2.0

import AppKit
import CoreGraphics

/// Marks keystrokes FutureT typed itself, so its own tap ignores them.
let futureTEventMarker: Int64 = 0x4655_5455   // "FUTU"

/// Watches the keyboard globally. Fail open: a key is swallowed only when a suggestion is on screen and the key is
/// one of the accept/dismiss keys; everything else passes through untouched, and if the tap is ever disabled the
/// keyboard simply works as normal.
final class KeyTap: @unchecked Sendable {
    enum Action { case acceptAll, acceptWord, dismiss }

    var onKey: (@Sendable () -> Void)?                          // any other key was pressed
    var onAction: (@Sendable (Action) -> Void)?

    private let lock = NSLock()
    private var _suggestionVisible = false
    var suggestionVisible: Bool {
        get { lock.withLock { _suggestionVisible } }
        set { lock.withLock { _suggestionVisible = newValue } }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    func start() -> Bool {
        guard tap == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type: type, event: event)
        }
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func stop() {
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false); CFMachPortInvalidate(t) }
        tap = nil; source = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type == .keyDown, event.getIntegerValueField(.eventSourceUserData) != futureTEventMarker else {
            return Unmanaged.passUnretained(event)
        }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let plain = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
        if suggestionVisible, plain {
            let action: Action? = switch code { case 48: .acceptAll; case 124: .acceptWord; case 53: .dismiss; default: nil }
            if let action {
                onAction?(action)
                return nil                                    // swallowed: the host app never sees this key
            }
        }
        onKey?()
        return Unmanaged.passUnretained(event)
    }
}
