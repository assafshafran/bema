import XCTest
@testable import Bema

final class ScriptAlignerTests: XCTestCase {
    private func aligner(_ script: String) -> ScriptAligner {
        ScriptAligner(words: ScriptText.tokens(script).map(ScriptText.normalize))
    }

    private let script = "PowerPoint still runs the slideshow, so animations and video keep working. Bema drives it in the background and keeps your notes in a window you control."

    func testFollowsExactSpeech() {
        let a = aligner(script)
        // "...so animations and video" -> next word is "keep" (index 9)
        XCTAssertEqual(a.align(heard: ["PowerPoint", "still", "runs", "the", "slideshow", "so", "animations", "and", "video"], from: 0), 9)
    }

    func testToleratesMisheardAndSkippedWords() {
        let a = aligner(script)
        // "animation" for "animations", "the" inserted, "video" dropped
        XCTAssertEqual(a.align(heard: ["so", "animation", "and", "the", "keep", "working"], from: 5), 11)
    }

    func testIgnoresUnrelatedSpeech() {
        let a = aligner(script)
        XCTAssertNil(a.align(heard: ["good", "morning", "everyone", "thanks", "for", "coming"], from: 0))
    }

    func testDoesNotJumpFarAheadOnACommonWord() {
        let a = aligner(script)
        // A lone "the" shouldn't move us to some later "the".
        XCTAssertNil(a.align(heard: ["the"], from: 12))
    }

    func testRecoversAfterSpeakerSkipsAhead() {
        let a = aligner(script)
        // Speaker skipped a sentence: "keeps your notes in a window"
        XCTAssertEqual(a.align(heard: ["keeps", "your", "notes", "in", "a", "window"], from: 3), 24)
    }

    func testHebrew() {
        // Made-up Hebrew: "Our deck shows how the team built a new tool for conference speakers"
        let a = aligner("המצגת שלנו מראה איך הצוות בנה כלי חדש למציגים בכנסים")
        XCTAssertEqual(a.align(heard: ["איך", "הצוות", "בנה", "כלי"], from: 0), 7)
    }

    func testNormalizeStripsPunctuationAndCase() {
        XCTAssertEqual(ScriptText.normalize("Slideshow,"), "slideshow")
        XCTAssertEqual(ScriptText.normalize("“Bema’s”"), "bemas")
    }
}

final class VoiceTargetTests: XCTestCase {
    func testIgnoresSmallBackwardRevisions() {
        var t = VoiceTarget(10)
        XCTAssertFalse(t.propose(9))
        XCTAssertFalse(t.propose(8))
        XCTAssertEqual(t.index, 10)
    }

    func testMovesAheadWhileReading() {
        var t = VoiceTarget(10)
        XCTAssertTrue(t.propose(12))
        XCTAssertTrue(t.propose(13))
        XCTAssertEqual(t.index, 13)
    }

    func testBigJumpsNeedConfirmation() {
        var t = VoiceTarget(10)
        XCTAssertFalse(t.propose(60))       // one stray match far ahead
        XCTAssertTrue(t.propose(61))        // confirmed by the next
        XCTAssertEqual(t.index, 61)
        XCTAssertFalse(t.propose(20))       // far back once: ignored
        XCTAssertFalse(t.propose(45))       // disagreeing match resets the pending jump
        XCTAssertEqual(t.index, 61)
    }
}

final class VoiceTargetEvidenceTests: XCTestCase {
    func testRepeatedPartialDoesNotConfirmAJump() {
        var t = VoiceTarget(10)
        XCTAssertFalse(t.propose(60, evidence: 5))
        XCTAssertFalse(t.propose(60, evidence: 5))   // same partial result again
        XCTAssertTrue(t.propose(61, evidence: 6))    // a new word heard, still far ahead
        XCTAssertEqual(t.index, 61)
    }
}

final class SmarterAlignmentTests: XCTestCase {
    private func aligner(_ script: String) -> ScriptAligner {
        ScriptAligner(words: ScriptText.tokens(script).map(ScriptText.normalize))
    }

    func testSplitWordMatchesJoinedScriptWord() {
        // Script: 0 Bema 1 drives 2 PowerPoint 3 through 4 AppleScript 5 so 6 nothing 7 changes
        let a = aligner("Bema drives PowerPoint through AppleScript so nothing changes")
        XCTAssertEqual(a.align(heard: ["drives", "PowerPoint", "through", "Apple", "script"], from: 2), 5)
        XCTAssertEqual(a.align(heard: ["drives", "power", "point", "through"], from: 1), 4)
    }

    func testJumpsForwardPastSkippedWords() {
        // Speaker skips "but it is still the industry standard for" and carries on.
        let a = aligner("PowerPoint is old but it is still the industry standard for decks and we love it")
        XCTAssertEqual(a.align(heard: ["PowerPoint", "is", "old", "decks", "and", "we"], from: 3), 14)
    }

    func testAdLibsDoNotBreakFollowing() {
        let a = aligner("Our numbers grew forty percent this quarter across every region")
        XCTAssertEqual(a.align(heard: ["numbers", "grew", "um", "honestly", "forty", "percent", "this"], from: 2), 6)
    }

    func testVocabularyPicksUnusualWords() {
        let vocab = ScriptText.vocabulary(from: [SlideInfo(id: 1, title: "How it works",
            notes: "Bema drives PowerPoint through AppleScript. The CRM and Q1 numbers come from Salesforce.", hidden: false)])
        for w in ["PowerPoint", "AppleScript", "CRM", "Q1", "Salesforce"] { XCTAssertTrue(vocab.contains(w), w) }
        XCTAssertFalse(vocab.contains("The"))
    }
}
