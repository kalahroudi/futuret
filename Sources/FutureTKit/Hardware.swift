// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(Darwin)
import Darwin
#endif

public func formatBytes(_ bytes: UInt64) -> String {
    let gb = Double(bytes) / 1_073_741_824
    if gb >= 1 { return String(format: "%.1f GB", gb) }
    return String(format: "%.0f MB", Double(bytes) / 1_048_576)
}

/// What the model picker needs to know about this Mac.
public struct Hardware: Equatable, Sendable {
    public var chip: String
    public var memoryBytes: UInt64
    public var isAppleSilicon: Bool

    public init(chip: String, memoryBytes: UInt64, isAppleSilicon: Bool) {
        self.chip = chip; self.memoryBytes = memoryBytes; self.isAppleSilicon = isAppleSilicon
    }

    public static func current() -> Hardware {
        func sysctlString(_ name: String) -> String? {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
            var buf = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
            return String(cString: buf)
        }
        let mem = ProcessInfo.processInfo.physicalMemory
        #if arch(arm64)
        let silicon = true
        #else
        let silicon = false
        #endif
        return Hardware(chip: sysctlString("machdep.cpu.brand_string") ?? "Unknown", memoryBytes: mem, isAppleSilicon: silicon)
    }
}
