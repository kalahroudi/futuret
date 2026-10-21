// SPDX-License-Identifier: Apache-2.0

import Foundation
import Darwin

/// Loopback port helpers.
public enum TCP {
    /// True when nothing is listening on `port` of the loopback address.
    public static func isPortFree(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        return result == 0
    }

    /// First free port from `start`, or nil.
    public static func firstFreePort(from start: Int, tries: Int = 30) -> Int? {
        (start..<(start + tries)).first { isPortFree($0) }
    }
}
