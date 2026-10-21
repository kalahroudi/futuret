// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum InstallStep: Int, CaseIterable, Sendable {
    case checkSystem, installUV, createEnvironment, installMLX, downloadModel

    public var title: String {
        switch self {
        case .checkSystem: return "Check your Mac"
        case .installUV: return "Install uv"
        case .createEnvironment: return "Create Python environment"
        case .installMLX: return "Install the model runtime"
        case .downloadModel: return "Download the writing model"
        }
    }
}

public enum InstallState: Equatable, Sendable {
    case pending, running, done(String), failed(String)
}

public struct InstallEvent: Sendable {
    public var step: InstallStep
    public var state: InstallState
    public var log: String?
}

public enum InstallError: Error, LocalizedError {
    case unsupported(String)
    case download(String)
    public var errorDescription: String? {
        switch self { case .unsupported(let m), .download(let m): return m }
    }
}

/// Installs uv, a private Python, mlx-lm and the model into the app folder. No admin rights, nothing global,
/// and no dependency on any other app: deleting the folder removes everything.
public final class Installer: @unchecked Sendable {
    public let paths: AppPaths
    private let session: URLSession
    public static let pythonVersion = "3.12"
    /// Pinned so every install behaves the same; bump together with a bench run.
    public static let mlxLMRequirement = "mlx-lm==0.32.2"

    public init(paths: AppPaths, session: URLSession = .shared) {
        self.paths = paths
        self.session = session
    }

    /// The runtime (not the model) is in place.
    public var runtimeInstalled: Bool { FileManager.default.isExecutableFile(atPath: paths.mlxServer.path) }

    public func modelInstalled(_ repo: String) -> Bool {
        let dir = paths.hfHome.appendingPathComponent("hub/models--" + repo.replacingOccurrences(of: "/", with: "--") + "/snapshots")
        let snaps = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return snaps.contains { s in
            let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent(s).path)) ?? []
            return files.contains { $0.hasSuffix(".safetensors") } && files.contains("config.json")
        }
    }

    static var uvTriple: String {
        #if arch(arm64)
        return "aarch64-apple-darwin"
        #else
        return "x86_64-apple-darwin"
        #endif
    }

    var uvEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["UV_CACHE_DIR"] = paths.uvCache.path
        env["UV_PYTHON_INSTALL_DIR"] = paths.pythonDir.path
        env["UV_NO_PROGRESS"] = "1"
        env["NO_COLOR"] = "1"
        return env
    }

    var hfEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["HF_HOME"] = paths.hfHome.path
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        env["PYTHONUNBUFFERED"] = "1"
        env["NO_COLOR"] = "1"
        return env
    }

    /// Runs every step, reporting progress. Steps that are already complete finish immediately.
    public func run(model: ModelChoice, onEvent: @escaping @Sendable (InstallEvent) -> Void) async throws {
        @Sendable func emit(_ step: InstallStep, _ state: InstallState, _ log: String? = nil) {
            onEvent(InstallEvent(step: step, state: state, log: log))
        }
        func fail(_ step: InstallStep, _ error: Error) -> Error {
            emit(step, .failed(error.localizedDescription), "✗ \(error.localizedDescription)")
            return error
        }
        try paths.ensureDirectories()

        emit(.checkSystem, .running)
        let hw = Hardware.current()
        guard hw.isAppleSilicon else { throw fail(.checkSystem, InstallError.unsupported("FutureT needs an Apple Silicon Mac.")) }
        emit(.checkSystem, .done("\(hw.chip) · \(formatBytes(hw.memoryBytes))"), "✓ \(hw.chip), \(formatBytes(hw.memoryBytes)) memory")

        emit(.installUV, .running)
        do {
            if !FileManager.default.isExecutableFile(atPath: paths.uv.path) {
                try await downloadUV { emit(.installUV, .running, $0) }
            }
            emit(.installUV, .done("uv ready"), "✓ uv at \(paths.uv.path)")
        } catch { throw fail(.installUV, error) }

        emit(.createEnvironment, .running)
        do {
            if !FileManager.default.isExecutableFile(atPath: paths.venvPython.path) {
                try await runCommand(paths.uv, ["venv", paths.venv.path, "--python", Self.pythonVersion],
                                     environment: uvEnvironment) { emit(.createEnvironment, .running, $0) }
            }
            emit(.createEnvironment, .done("Python \(Self.pythonVersion)"), "✓ Python environment ready")
        } catch { throw fail(.createEnvironment, error) }

        emit(.installMLX, .running)
        do {
            if !runtimeInstalled {
                try await runCommand(paths.uv, ["pip", "install", "--no-cache", "--python", paths.venvPython.path, Self.mlxLMRequirement],
                                     environment: uvEnvironment) { emit(.installMLX, .running, $0) }
            }
            emit(.installMLX, .done(Self.mlxLMRequirement), "✓ \(Self.mlxLMRequirement)")
        } catch { throw fail(.installMLX, error) }

        emit(.downloadModel, .running)
        do {
            if !modelInstalled(model.repo) { try await downloadModel(model.repo) { emit(.downloadModel, .running, $0) } }
            emit(.downloadModel, .done(model.title), "✓ \(model.title) ready")
        } catch { throw fail(.downloadModel, error) }
    }

    /// Downloads a model into the app's own Hugging Face home. Resumes a partial download.
    public func downloadModel(_ repo: String, onLine: @escaping @Sendable (String) -> Void) async throws {
        let script = "import sys; from huggingface_hub import snapshot_download; print(snapshot_download(sys.argv[1]))"
        onLine("Downloading \(repo)…")
        try await runCommand(paths.venvPython, ["-c", script, repo], environment: hfEnvironment, onLine: onLine)
    }

    func downloadUV(log: @escaping @Sendable (String) -> Void) async throws {
        let url = URL(string: "https://github.com/astral-sh/uv/releases/latest/download/uv-\(Self.uvTriple).tar.gz")!
        log("Downloading uv (\(Self.uvTriple))…")
        let (tmp, response) = try await session.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw InstallError.download("uv download failed (HTTP \(http.statusCode))")
        }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("futuret-uv-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let extracted = work.appendingPathComponent("out", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        try await runCommand(URL(fileURLWithPath: "/usr/bin/tar"), ["-xzf", tmp.path, "-C", extracted.path, "--strip-components=1"],
                             environment: [:]) { log($0) }
        try fm.createDirectory(at: paths.bin, withIntermediateDirectories: true)
        if fm.fileExists(atPath: paths.uv.path) { try fm.removeItem(at: paths.uv) }
        try fm.moveItem(at: extracted.appendingPathComponent("uv"), to: paths.uv)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: paths.uv.path)
        try? fm.removeItem(at: tmp)
    }
}
