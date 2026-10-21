import XCTest
@testable import FutureTKit

final class EngineTests: XCTestCase {
    func testPromptPutsUserTextLastAndKeepsHeaderStable() {
        let a = PromptBuilder.build(CompletionContext(appName: "Mail", style: "Formal.", phrases: ["Best regards,"], before: "Dear Sam, thanks"))
        let b = PromptBuilder.build(CompletionContext(appName: "Mail", style: "Formal.", phrases: ["Best regards,"], before: "Dear Sam, thanks for"))
        XCTAssertTrue(a.hasSuffix("Dear Sam, thanks"))
        let common = a.commonPrefix(with: b)
        XCTAssertTrue(common.hasSuffix("Dear Sam, thanks"), "typing more must keep everything before the cursor identical so the cache is reused")
        XCTAssertTrue(a.contains("Mail") && a.contains("Formal.") && a.contains("Best regards,"))
    }

    func testPromptTrimsLongTextAtAWordBoundary() {
        let long = String(repeating: "alpha beta ", count: 400)
        let p = PromptBuilder.build(CompletionContext(before: long))
        let body = p.components(separatedBy: "---\n").last ?? ""
        XCTAssertLessThanOrEqual(body.count, PromptBuilder.maxBeforeChars)
        XCTAssertTrue(body.hasPrefix("alpha") || body.hasPrefix("beta"))
    }

    func testCleanerBasics() {
        XCTAssertEqual(SuggestionCleaner.clean(" the beginning", before: "move to", length: .phrase, truncated: false), " the beginning")
        XCTAssertEqual(SuggestionCleaner.clean(" soon", before: "see you ", length: .phrase, truncated: false), "soon", "no doubled space")
        XCTAssertEqual(SuggestionCleaner.clean("\nnext line", before: "x", length: .phrase, truncated: false), "next line")
        XCTAssertNil(SuggestionCleaner.clean("   ", before: "x", length: .phrase, truncated: false))
        XCTAssertEqual(SuggestionCleaner.clean(" one two thr", before: "a", length: .phrase, truncated: true), " one two", "drops a word cut by the token limit")
        XCTAssertEqual(SuggestionCleaner.clean(" Yes. And more", before: "a", length: .sentence, truncated: false), " Yes.")
        XCTAssertNil(SuggestionCleaner.clean("thanks for sending", before: "Hi, thanks for sending", length: .phrase, truncated: false), "repeating typed text is not a suggestion")
    }

    func testLengthsAreOrdered() {
        let t = CompletionLength.allCases.map(\.maxTokens)
        XCTAssertEqual(t, t.sorted())
    }

    func testRecommendedModelFitsTheMac() {
        let gb: UInt64 = 1_073_741_824
        XCTAssertEqual(ModelCatalog.recommended(memoryBytes: 8 * gb).repo, "mlx-community/Qwen2.5-1.5B-4bit")
        XCTAssertEqual(ModelCatalog.recommended(memoryBytes: 64 * gb).repo, "mlx-community/gemma-3-4b-pt-4bit")
        for mem in [8, 16, 24, 36, 64] {
            XCTAssertLessThanOrEqual(ModelCatalog.recommended(memoryBytes: UInt64(mem) * gb).minMemoryGB, mem)
        }
    }

    func testServerArgumentsAreLoopbackOnly() {
        let a = ModelServer.arguments(repo: "x/y", port: 12345)
        XCTAssertEqual(a[a.firstIndex(of: "--host")! + 1], "127.0.0.1")
        XCTAssertEqual(a[a.firstIndex(of: "--port")! + 1], "12345")
    }

    func testModelInstalledDetection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let paths = AppPaths(root: root)
        let installer = Installer(paths: paths)
        XCTAssertFalse(installer.modelInstalled("a/b"))
        let snap = paths.hfHome.appendingPathComponent("hub/models--a--b/snapshots/abc")
        try FileManager.default.createDirectory(at: snap, withIntermediateDirectories: true)
        try Data().write(to: snap.appendingPathComponent("config.json"))
        XCTAssertFalse(installer.modelInstalled("a/b"), "weights missing")
        try Data().write(to: snap.appendingPathComponent("model.safetensors"))
        XCTAssertTrue(installer.modelInstalled("a/b"))
    }

    func testPortHelpers() {
        let p = TCP.firstFreePort(from: 41_000)
        XCTAssertNotNil(p)
        XCTAssertTrue(TCP.isPortFree(p!))
    }
}
