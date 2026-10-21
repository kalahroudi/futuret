// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ModelServerError: Error, LocalizedError, Equatable {
    case notInstalled, exited(Int32, String), timeout, cancelled, portBusy(Int), badResponse(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled: return "The model runtime is not installed yet."
        case .exited(let c, let tail): return "The model server exited with code \(c). \(tail)"
        case .timeout: return "The model took too long to load."
        case .cancelled: return "Cancelled."
        case .portBusy(let p): return "Port \(p) is in use by another program."
        case .badResponse(let m): return "Unexpected answer from the model: \(m)"
        }
    }
}

public enum ModelServerState: Equatable, Sendable {
    case stopped, loading(String), running, failed(String)
    public var isActive: Bool { switch self { case .loading, .running: return true; default: return false } }
}

/// Runs one `mlx_lm.server` bound to loopback, only while it is needed.
/// - one process at a time; a stop or new start cancels a load in progress
/// - stopping waits until the process tree is gone, so its memory really comes back
/// - the pid is recorded so a crashed app reaps a leftover server on the next launch
/// - "running" means the model answered a real request, not just that the port opened
public actor ModelServer {
    private let paths: AppPaths
    private let logs: LogBuffer
    private var process: ManagedProcess?
    private var generation = 0
    public private(set) var state: ModelServerState = .stopped
    public private(set) var port = 0
    public private(set) var repo: String?
    private let current = CurrentProcess()

    public init(paths: AppPaths, logs: LogBuffer = LogBuffer(capacity: 300)) {
        self.paths = paths
        self.logs = logs
    }

    public var processID: Int32? { process?.isRunning == true ? process?.processIdentifier : nil }
    /// Real memory the server uses (physical footprint, includes GPU memory MLX wires).
    public var footprintBytes: UInt64 { processID.map { ProcessTree.footprint(of: $0) } ?? 0 }
    public var recentLog: [String] { logs.snapshot }

    /// Kills the server right now, from any thread. Used while quitting.
    public nonisolated func killNow() { current.process?.killNow(); try? FileManager.default.removeItem(at: paths.serverPidFile) }

    /// Call once at launch: a server left behind by a crash or force quit would hold gigabytes.
    public nonisolated func reapOrphan() { PIDRecord.reapOrphan(at: paths.serverPidFile) }

    static func arguments(repo: String, port: Int) -> [String] {
        ["--model", repo, "--host", "127.0.0.1", "--port", String(port),
         "--temp", "0.2", "--top-p", "0.9",
         "--max-tokens", "96",
         "--prompt-cache-size", "8", "--prompt-cache-bytes", "268435456",
         "--log-level", "WARNING"]
    }

    func environment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = paths.venvBin.path + ":" + (env["PATH"] ?? "/usr/bin:/bin")
        env["PYTHONUNBUFFERED"] = "1"
        env["HF_HOME"] = paths.hfHome.path
        env["HF_HUB_OFFLINE"] = "1"                 // the model is already on disk; never touch the network at runtime
        env["HF_HUB_DISABLE_TELEMETRY"] = "1"
        return env
    }

    /// Starts the server and waits until the model answers.
    public func start(repo: String, port requested: Int? = nil) async throws {
        generation += 1
        let mine = generation
        if process != nil { await terminateCurrent() }
        guard mine == generation else { throw ModelServerError.cancelled }
        guard FileManager.default.isExecutableFile(atPath: paths.mlxServer.path) else {
            state = .failed("Not installed"); throw ModelServerError.notInstalled
        }
        let chosen = requested ?? (TCP.firstFreePort(from: Int.random(in: 20_000..<40_000)) ?? 0)
        guard chosen > 0, TCP.isPortFree(chosen) else { state = .failed("Port busy"); throw ModelServerError.portBusy(chosen) }
        state = .loading("Loading model…")
        self.repo = repo; port = chosen

        let logs = self.logs
        let p = ManagedProcess(executable: paths.mlxServer, arguments: Self.arguments(repo: repo, port: chosen),
                               environment: environment()) { logs.append($0) }
        do { try p.start() } catch { state = .failed(error.localizedDescription); throw error }
        process = p; current.process = p
        if let t = ProcessTree.startTime(of: p.processIdentifier) {
            PIDRecord.write(PIDRecord(pid: p.processIdentifier, startTime: t), to: paths.serverPidFile)
        }

        let deadline = Date().addingTimeInterval(300)
        while Date() < deadline {
            if mine != generation { throw ModelServerError.cancelled }
            if !p.isRunning {
                let code = await p.waitUntilExit()
                if process === p { process = nil; current.process = nil }
                try? FileManager.default.removeItem(at: paths.serverPidFile)
                state = .failed("Server stopped")
                throw ModelServerError.exited(code, p.recentOutput.suffix(3).joined(separator: " "))
            }
            if await Self.isUp(port: chosen), await Self.warmUp(port: chosen) {
                if mine != generation { throw ModelServerError.cancelled }
                state = .running
                return
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        if mine == generation { await terminateCurrent(); state = .failed("Timed out") }
        throw ModelServerError.timeout
    }

    public func stop() async {
        generation += 1
        await terminateCurrent()
        state = .stopped
    }

    private func terminateCurrent() async {
        guard let p = process else { return }
        p.terminate(grace: 2)
        _ = await p.waitUntilExit()
        for c in ProcessTree.descendants(of: p.processIdentifier) where ProcessTree.isAlive(c) { kill(c, SIGKILL) }
        if process === p { process = nil; current.process = nil }
        try? FileManager.default.removeItem(at: paths.serverPidFile)
    }

    static func isUp(port: Int) async -> Bool {
        guard let url = URL(string: "http://127.0.0.1:\(port)/v1/models") else { return false }
        var req = URLRequest(url: url); req.timeoutInterval = 2
        return ((try? await URLSession.shared.data(for: req).1 as? HTTPURLResponse)?.statusCode) == 200
    }

    static func warmUp(port: Int) async -> Bool {
        (try? await CompletionClient(port: port).complete(prompt: "Hello", maxTokens: 1, stop: [])) != nil
    }
}

final class CurrentProcess: @unchecked Sendable {
    private let lock = NSLock()
    private var _p: ManagedProcess?
    var process: ManagedProcess? {
        get { lock.withLock { _p } }
        set { lock.withLock { _p = newValue } }
    }
}

/// Talks to the loopback server's raw text-completion endpoint.
public struct CompletionClient: Sendable {
    public struct Result: Sendable { public var text: String; public var truncated: Bool; public var promptTokens: Int; public var completionTokens: Int }
    public let port: Int
    public init(port: Int) { self.port = port }

    public func complete(prompt: String, maxTokens: Int, stop: [String], temperature: Double = 0.2, timeout: TimeInterval = 20) async throws -> Result {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/completions")!)
        req.httpMethod = "POST"; req.timeoutInterval = timeout
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["prompt": prompt, "max_tokens": maxTokens, "temperature": temperature, "stream": false,
                                   "repetition_penalty": 1.15, "repetition_context_size": 64]
        if !stop.isEmpty { body["stop"] = stop }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (obj["choices"] as? [[String: Any]])?.first, let text = choice["text"] as? String
        else { throw ModelServerError.badResponse(String(decoding: data.prefix(200), as: UTF8.self)) }
        let usage = obj["usage"] as? [String: Any]
        return Result(text: text, truncated: (choice["finish_reason"] as? String) == "length",
                      promptTokens: usage?["prompt_tokens"] as? Int ?? 0, completionTokens: usage?["completion_tokens"] as? Int ?? 0)
    }
}
