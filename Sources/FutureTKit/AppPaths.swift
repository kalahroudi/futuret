// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Every file the app owns lives under one folder, so uninstalling is deleting it.
/// Never scatter state across ~/.something, /tmp and UserDefaults without listing it here.
public struct AppPaths: Sendable {
    public let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FutureT", isDirectory: true)
    }

    public var updateDir: URL { root.appendingPathComponent("update", isDirectory: true) }
    public var settingsFile: URL { root.appendingPathComponent("settings.json") }
    /// Written by the running app so the MCP server can find it (loopback port + token), 0600.
    public var controlFile: URL { root.appendingPathComponent("control.json") }

    // Private model runtime: uv, its Python, a venv with mlx-lm, and the model files. Nothing global.
    public var bin: URL { root.appendingPathComponent("bin", isDirectory: true) }
    public var uv: URL { bin.appendingPathComponent("uv") }
    public var uvCache: URL { root.appendingPathComponent("cache", isDirectory: true) }
    public var pythonDir: URL { root.appendingPathComponent("python", isDirectory: true) }
    public var venv: URL { root.appendingPathComponent("venv", isDirectory: true) }
    public var venvBin: URL { venv.appendingPathComponent("bin", isDirectory: true) }
    public var venvPython: URL { venvBin.appendingPathComponent("python") }
    public var mlxServer: URL { venvBin.appendingPathComponent("mlx_lm.server") }
    /// Hugging Face home for this app only, so models live (and are deleted) with the app folder.
    public var hfHome: URL { root.appendingPathComponent("models", isDirectory: true) }
    public var serverPidFile: URL { root.appendingPathComponent("server.pid") }
    public var logsDir: URL { root.appendingPathComponent("logs", isDirectory: true) }

    public func ensureDirectories() throws {
        for dir in [root, updateDir, bin, uvCache, pythonDir, hfHome, logsDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
