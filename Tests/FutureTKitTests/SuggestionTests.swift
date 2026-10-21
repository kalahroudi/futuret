import XCTest
@testable import FutureTKit

final class SuggestionTests: XCTestCase {
    func testTypingTheSuggestionKeepsItAlive() {
        var s = SuggestionSession(anchor: "Could we move", suggestion: " the sync to Thursday")
        XCTAssertEqual(s.reconcile(currentBefore: "Could we move"), .unchanged)
        XCTAssertEqual(s.reconcile(currentBefore: "Could we moveth"), .invalid, "a missing space is a different path")
        var t = SuggestionSession(anchor: "Could we move", suggestion: " the sync to Thursday")
        XCTAssertEqual(t.reconcile(currentBefore: "Could we move the"), .advanced)
        XCTAssertEqual(t.remaining, " sync to Thursday")
        XCTAssertEqual(t.reconcile(currentBefore: "Could we move the sync to Thursday"), .finished)
    }

    func testOtherTypingOrDeletionInvalidates() {
        var s = SuggestionSession(anchor: "Hello", suggestion: " there")
        XCTAssertEqual(s.reconcile(currentBefore: "Hello,"), .invalid)
        var d = SuggestionSession(anchor: "Hello", suggestion: " there")
        XCTAssertEqual(d.reconcile(currentBefore: "Hell"), .invalid)
    }

    func testWordByWordAcceptance() {
        var s = SuggestionSession(anchor: "Can we", suggestion: " move it, please")
        XCTAssertEqual(s.nextWord, " move")
        s.accepted(s.nextWord)
        XCTAssertEqual(s.nextWord, " it,")
        s.accepted(s.nextWord)
        XCTAssertEqual(s.remaining, " please")
        XCTAssertEqual(s.anchor, "Can we move it,")
        XCTAssertEqual(SuggestionSession.firstWord(of: "don't stop"), "don't")
    }

    func testContextGuard() {
        XCTAssertTrue(ContextGuard.shouldHold(before: "see https://exa"))
        XCTAssertTrue(ContextGuard.shouldHold(before: "ping @ma"))
        XCTAssertTrue(ContextGuard.shouldHold(before: "mail sam@exa"))
        XCTAssertTrue(ContextGuard.shouldHold(before: "card 4111111111"))
        XCTAssertFalse(ContextGuard.shouldHold(before: "see you in 2 days"))
        XCTAssertFalse(ContextGuard.shouldHold(before: "see https://example.com "), "after a space the link is done")
    }

    func testFieldPolicy() {
        let p = FieldPolicy(disabledApps: ["com.example.off"])
        XCTAssertEqual(p.evaluate(bundleID: "com.apple.mail", role: "AXTextArea", subrole: nil, isEditable: true), .allowed)
        XCTAssertFalse(p.evaluate(bundleID: "com.apple.mail", role: "AXTextField", subrole: "AXSecureTextField", isEditable: true).isAllowed)
        XCTAssertFalse(p.evaluate(bundleID: "com.1password.1password", role: "AXTextArea", subrole: nil, isEditable: true).isAllowed)
        XCTAssertFalse(p.evaluate(bundleID: "com.example.off", role: "AXTextArea", subrole: nil, isEditable: true).isAllowed)
        XCTAssertFalse(p.evaluate(bundleID: "com.apple.mail", role: "AXStaticText", subrole: nil, isEditable: false).isAllowed)
        XCTAssertFalse(p.evaluate(bundleID: "x", role: "AXTextField", subrole: "AXSearchField", isEditable: true).isAllowed)
        XCTAssertFalse(FieldPolicy(enabled: false).evaluate(bundleID: nil, role: "AXTextArea", subrole: nil, isEditable: true).isAllowed)
    }

    func testPlacementInlineThenCard() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        let caret = CGRect(x: 400, y: 500, width: 1, height: 18)
        let inline = CaretPlacement.place(caret: caret, textWidth: 200, lineHeight: 18, screen: screen)
        XCTAssertEqual(inline.style, .inline)
        XCTAssertEqual(inline.frame.minX, 401)
        let nearEdge = CGRect(x: 900, y: 500, width: 1, height: 18)
        let card = CaretPlacement.place(caret: nearEdge, textWidth: 200, lineHeight: 18, screen: screen)
        XCTAssertEqual(card.style, .card)
        XCTAssertTrue(screen.contains(card.frame))
    }

    func testFlipCoordinates() {
        let r = CaretPlacement.flip(CGRect(x: 10, y: 100, width: 2, height: 20), mainScreenHeight: 900)
        XCTAssertEqual(r.minY, 780)
    }

    func testHintModes() {
        XCTAssertTrue(KeyHintMode.untilLearned.shouldShow(acceptedCount: 9))
        XCTAssertFalse(KeyHintMode.untilLearned.shouldShow(acceptedCount: 10))
        XCTAssertTrue(KeyHintMode.always.shouldShow(acceptedCount: 999))
        XCTAssertFalse(KeyHintMode.never.shouldShow(acceptedCount: 0))
    }
}
