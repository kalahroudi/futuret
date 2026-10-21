// SPDX-License-Identifier: Apache-2.0

import Foundation
import FutureTKit

// futuret-cli setup <root> [repo]          install runtime + model into <root> (never touches the real app folder unless asked)
// futuret-cli bench <root> <repo> [repo…]  measure load time, memory and suggestion latency
setvbuf(stdout, nil, _IOLBF, 0)

func fail(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(1) }
let args = Array(CommandLine.arguments.dropFirst())
guard args.count >= 2 else { fail("usage: futuret-cli setup <root> [repo] | bench <root> <repo>…") }
let paths = AppPaths(root: URL(fileURLWithPath: (args[1] as NSString).expandingTildeInPath, isDirectory: true))

func choice(_ repo: String) -> ModelChoice {
    ModelCatalog.all.first { $0.repo == repo } ?? ModelChoice(repo: repo, title: repo, sizeGB: 0, minMemoryGB: 0, note: "custom")
}

func install(_ repo: String) async throws {
    let started = Date()
    try await Installer(paths: paths).run(model: choice(repo)) { e in
        if let l = e.log { print("[\(e.step.title)] \(l)") }
    }
    print(String(format: "setup finished in %.1fs", Date().timeIntervalSince(started)))
}

let samples: [(app: String, before: String)] = [
    ("Mail", "Hi Sam,\n\nThanks for sending the draft over. I read it twice and I think the structure works well. Could we move the sync to"),
    ("Slack", "hey, quick question about the deploy — did you"),
    ("Notes", "Ideas for the offsite: 1) a half day workshop on"),
    ("Mail", "Dear Ms. Alvarez, I am writing to follow up on our conversation last week regarding the"),
]

func percentile(_ xs: [Double], _ p: Double) -> Double {
    let s = xs.sorted(); guard !s.isEmpty else { return 0 }
    return s[min(s.count - 1, Int(Double(s.count - 1) * p))]
}

func bench(_ repo: String) async throws {
    print("\n=== \(repo)")
    if !Installer(paths: paths).modelInstalled(repo) { try await install(repo) }
    let server = ModelServer(paths: paths)
    let t0 = Date()
    try await server.start(repo: repo)
    let load = Date().timeIntervalSince(t0)
    let port = await server.port
    let client = CompletionClient(port: port)
    let mem = await server.footprintBytes
    print(String(format: "load %.1fs · memory %@", load, formatBytes(mem)))

    // Typing simulation: grow the same text a few characters at a time, as a user would, so the prompt cache is exercised.
    var cold: [Double] = [], typing: [Double] = [], toks: [Double] = []
    for (app, text) in samples {
        var shown = ""
        for len in CompletionLength.allCases {
            let ctx = CompletionContext(appName: app, style: "Natural, clear.", before: text)
            let t = Date()
            let r = try await client.complete(prompt: PromptBuilder.build(ctx), maxTokens: len.maxTokens, stop: len.stop)
            let dt = Date().timeIntervalSince(t)
            if len == .sentence {
                cold.append(dt * 1000)
                shown = SuggestionCleaner.clean(r.text, before: text, length: len, truncated: r.truncated) ?? "(none)"
                if r.completionTokens > 0 { toks.append(Double(r.completionTokens) / dt) }
            }
        }
        print("  [\(app)] …\(text.suffix(40)) ▸ \(shown)")
        // incremental: add 3 characters at a time over the next words of the suggestion
        let chars = Array(shown)
        var i = 0
        while i + 3 <= min(chars.count, 24) {
            i += 3
            let ctx = CompletionContext(appName: app, style: "Natural, clear.", before: text + String(chars[0..<i]))
            let t = Date()
            _ = try await client.complete(prompt: PromptBuilder.build(ctx), maxTokens: CompletionLength.phrase.maxTokens, stop: ["\n"])
            typing.append(Date().timeIntervalSince(t) * 1000)
        }
    }
    let peak = await server.footprintBytes
    print(String(format: "sentence, first request per text: p50 %.0f ms · p95 %.0f ms · %.0f tok/s", percentile(cold, 0.5), percentile(cold, 0.95), toks.reduce(0, +) / Double(max(toks.count, 1))))
    print(String(format: "while typing (phrase):            p50 %.0f ms · p95 %.0f ms (%d requests)", percentile(typing, 0.5), percentile(typing, 0.95), typing.count))
    print("memory after run: \(formatBytes(peak))")
    await server.stop()
    try? await Task.sleep(nanoseconds: 500_000_000)
    print("server stopped; process gone: \(await server.processID == nil)")
}

let task = Task {
    do {
        switch args[0] {
        case "setup": try await install(args.count > 2 ? args[2] : ModelCatalog.recommended(memoryBytes: Hardware.current().memoryBytes).repo)
        case "bench": for repo in args.dropFirst(2) { try await bench(repo) }
        default: fail("unknown command \(args[0])")
        }
        exit(0)
    } catch { fail("error: \(error.localizedDescription)") }
}
_ = task
dispatchMain()
