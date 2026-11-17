import SwiftUI
import XCTest
@testable import Bema

final class NotePromptTests: XCTestCase {
    private let brief = SlideBrief(deckName: "Acme Launch", number: 3, count: 12, title: "Three shifts",
                                   text: "Drafting\nDelivery\nFeedback", previousTitle: "Welcome", nextTitle: "Numbers",
                                   picture: nil)

    func testPromptCarriesTheSlideAndItsNeighbours() {
        let p = NotePrompt.prompt(brief)
        XCTAssertTrue(p.contains("Presentation: Acme Launch"))
        XCTAssertTrue(p.contains("Slide 3 of 12."))
        XCTAssertTrue(p.contains("Previous slide: Welcome"))
        XCTAssertTrue(p.contains("Next slide: Numbers"))
        XCTAssertTrue(p.contains("Title: Three shifts"))
        XCTAssertTrue(p.contains("Drafting\nDelivery\nFeedback"))
        XCTAssertFalse(p.contains("picture"))
    }

    func testLongSlideTextIsCut() {
        var b = brief
        b.text = String(repeating: "a", count: 10_000)
        XCTAssertLessThan(NotePrompt.prompt(b).count, 3_400)
    }

    func testSlideWithOnlyAPicture() {
        var b = brief
        b.text = "  "
        b.picture = Data([1, 2, 3])
        XCTAssertTrue(NotePrompt.prompt(b).contains("The slide has no text; the picture shows it."))
    }

    func testCleanRemovesPreamblesBulletsAndFences() {
        let raw = """
        Here are the speaker notes for slide 3:
        ```
        - I see **three shifts** coming.
        • Drafting is already solved.
        2. Delivery is next.
        ## Feedback closes the loop.
        ```
        """
        XCTAssertEqual(NotePrompt.clean(raw), "I see **three shifts** coming.\nDrafting is already solved.\nDelivery is next.\nFeedback closes the loop.")
    }

    func testCleanRemovesWrappingQuotesAndKeepsHebrew() {
        XCTAssertEqual(NotePrompt.clean("“שלום לכולם.\nהיום נדבר על הצגה.”"), "שלום לכולם.\nהיום נדבר על הצגה.")
        XCTAssertEqual(NotePrompt.clean("Say hello.\n\n\n\nThen the agenda."), "Say hello.\n\nThen the agenda.")
    }

    // MARK: Claude

    func testClaudeRequestPutsThePictureFirstAndAsksForFallbacks() throws {
        var b = brief
        b.picture = Data([0x89, 0x50])
        let body = ClaudeAPI.body(model: "claude-opus-5-5", brief: b)
        XCTAssertEqual(body["model"] as? String, "claude-opus-5-5")
        XCTAssertEqual(body["fallbacks"] as? String, "default")
        XCTAssertEqual((body["output_config"] as? [String: String])?["effort"], "medium")
        let content = try XCTUnwrap(((body["messages"] as? [[String: Any]])?.first?["content"]) as? [[String: Any]])
        XCTAssertEqual(content.map { $0["type"] as? String }, ["image", "text"])
        XCTAssertNotNil(try? JSONSerialization.data(withJSONObject: body))
        XCTAssertEqual(ClaudeAPI.headers(key: "k", model: "claude-opus-5-5")["anthropic-beta"], ClaudeAPI.fallbackBeta)
    }

    func testOtherClaudeModelsGetNoFallbacks() {
        let body = ClaudeAPI.body(model: "claude-haiku-5-5", brief: brief)
        XCTAssertNil(body["fallbacks"])
        XCTAssertNil(ClaudeAPI.headers(key: "k", model: "claude-haiku-5-5")["anthropic-beta"])
    }

    func testClaudeResponses() throws {
        let ok = #"{"content":[{"type":"thinking","thinking":""},{"type":"text","text":"Say hello."}],"stop_reason":"end_turn"}"#
        XCTAssertEqual(try ClaudeAPI.parse(Data(ok.utf8)), "Say hello.")
        let refusal = #"{"content":[],"stop_reason":"refusal"}"#
        XCTAssertThrowsError(try ClaudeAPI.parse(Data(refusal.utf8))) { XCTAssertEqual($0 as? NoteWriterError, .refused) }
        let error = #"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#
        XCTAssertThrowsError(try ClaudeAPI.parse(Data(error.utf8))) {
            XCTAssertEqual($0 as? NoteWriterError, .server("Claude: invalid x-api-key"))
        }
    }

    // MARK: OpenAI-style (OpenAI, Ollama, LM Studio)

    func testChatEndpoints() {
        XCTAssertEqual(ChatAPI.endpoint(base: "http://localhost:11434/v1/")?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(ChatAPI.endpoint(base: "http://localhost:1234/v1/chat/completions")?.absoluteString, "http://localhost:1234/v1/chat/completions")
        XCTAssertEqual(ChatAPI.modelsEndpoint(base: "http://localhost:11434/v1")?.absoluteString, "http://localhost:11434/v1/models")
    }

    func testChatRequestSendsThePictureOnlyWhenAsked() throws {
        var b = brief
        b.picture = Data([1])
        let withPicture = ChatAPI.body(model: "m", brief: b, sendPicture: true)
        let user = try XCTUnwrap((withPicture["messages"] as? [[String: Any]])?.last)
        XCTAssertEqual((user["content"] as? [[String: Any]])?.last?["type"] as? String, "image_url")
        let textOnly = ChatAPI.body(model: "m", brief: b, sendPicture: false)
        let plain = try XCTUnwrap((textOnly["messages"] as? [[String: Any]])?.last?["content"] as? String)
        XCTAssertFalse(plain.contains("picture"))
    }

    func testChatResponses() throws {
        let ok = #"{"choices":[{"message":{"role":"assistant","content":"Say hello."}}]}"#
        XCTAssertEqual(try ChatAPI.parse(Data(ok.utf8), who: "OpenAI"), "Say hello.")
        let error = #"{"error":{"message":"model 'x' not found"}}"#
        XCTAssertThrowsError(try ChatAPI.parse(Data(error.utf8), who: "The local model")) {
            XCTAssertEqual($0 as? NoteWriterError, .server("The local model: model 'x' not found"))
        }
        XCTAssertEqual(ChatAPI.parseModels(Data(#"{"data":[{"id":"qwen3"},{"id":"llama3.2"}]}"#.utf8)), ["llama3.2", "qwen3"])
    }

    func testSettingsRoundTrip() {
        let d = UserDefaults(suiteName: "bema-tests-\(UUID().uuidString)")!
        XCTAssertNil(NoteWriterSettings.load(d).kind)
        var s = NoteWriterSettings()
        s.kind = .local
        s.localModel = "llama3.2"
        s.localSendsPicture = true
        s.save(d)
        XCTAssertEqual(NoteWriterSettings.load(d), s)
    }

    func testAppleScriptTextKeepsLinesAndQuotes() {
        XCTAssertEqual(AppleScriptText.literal("Say \"hi\"\nThen go"), #""Say \"hi\"" & return & "Then go""#)
    }

    func testClaudeAppRequest() {
        XCTAssertTrue(ClaudeAppRequest.text(slides: [4], deckName: "Acme", allMissing: false).contains("slide 4 of my presentation “Acme”"))
        XCTAssertTrue(ClaudeAppRequest.text(slides: [1, 2], deckName: "", allMissing: true).contains("the slides in my presentation that have none"))
    }
}

final class DraftNotesTests: XCTestCase {
    private let slides = [
        SlideInfo(id: 1, title: "Welcome", notes: "Say hello.", hidden: false),
        SlideInfo(id: 2, title: "Shifts", notes: "", hidden: false),
        SlideInfo(id: 3, title: "Spare", notes: "", hidden: true),
        SlideInfo(id: 4, title: "Numbers", notes: " \n", hidden: false),
    ]

    func testDraftsFillEmptySlidesAndEditsReplaceDeckNotes() {
        let merged = DraftNotes.merge(slides, [1: "Say hello, then the agenda.", 2: "Three shifts."])
        XCTAssertEqual(merged[0].notes, "Say hello, then the agenda.")
        XCTAssertTrue(merged[0].draft)
        XCTAssertEqual(merged[1].notes, "Three shifts.")
        XCTAssertTrue(merged[1].draft)
        XCTAssertFalse(merged[2].draft)
    }

    func testAnEditThatMatchesTheDeckIsNotADraft() {
        let merged = DraftNotes.merge(slides, [1: "Say hello.\n"])
        XCTAssertFalse(merged[0].draft)
        XCTAssertTrue(DraftNotes.same("A\r\nB ", "A\nB"))
    }

    @MainActor func testEditingNotesInBema() {
        let model = PresenterModel()
        model.deckSlides = slides
        model.setDraft("Say hello.\nThen the agenda.", for: 1)
        XCTAssertTrue(model.draftReplacesDeckNotes(1))
        XCTAssertEqual(model.slides[0].notes, "Say hello.\nThen the agenda.")
        model.setDraft("  Say hello. ", for: 1)          // back to what the deck says
        XCTAssertNil(model.drafts[1])
        XCTAssertFalse(model.slides[0].draft)
        model.setDraft("Typed by hand.", for: 2)
        XCTAssertFalse(model.draftReplacesDeckNotes(2))
        model.discardDraft(for: 2)
        XCTAssertEqual(model.slides[1].notes, "")
    }

    func testSlidesNeedingNotesSkipHiddenAndDrafted() {
        XCTAssertEqual(DraftNotes.needingNotes(slides), [2, 4])
        XCTAssertEqual(DraftNotes.needingNotes(DraftNotes.merge(slides, [2: "x"])), [4])
    }

    func testPruneDropsDraftsTheDeckNoLongerNeeds() {
        XCTAssertEqual(DraftNotes.pruned([1: "a", 2: "b", 9: "c", 4: "", 3: "Say hello."], for: slides), [1: "a", 2: "b", 3: "Say hello."])
        XCTAssertEqual(DraftNotes.pruned([1: "Say hello."], for: slides), [:])
    }

    func testDraftsAreKeptPerDeck() {
        let deck = URL(fileURLWithPath: "/tmp/bema-test-\(UUID().uuidString).pptx")
        DraftNotes.save([2: "Three shifts.\nThen numbers."], for: deck)
        XCTAssertEqual(DraftNotes.load(for: deck), [2: "Three shifts.\nThen numbers."])
        DraftNotes.save([:], for: deck)
        XCTAssertEqual(DraftNotes.load(for: deck), [:])
    }
}

@MainActor
private final class FakeDeck: MCPDeck {
    var mcpDeckName: String? = "Acme Launch"
    var mcpAppName = "PowerPoint"
    var mcpCurrentSlide = 2
    var mcpSlides = [SlideInfo(id: 1, title: "Welcome", notes: "Say hello.", hidden: false),
                     SlideInfo(id: 2, title: "Shifts", notes: "", hidden: false)]
    var saved: [Int: String] = [:]
    func mcpSlideText(_ id: Int) -> String { id == 2 ? "Drafting · Delivery" : "" }
    func mcpSlidePNG(_ id: Int) -> Data? { id == 2 ? Data([0x89]) : nil }
    func mcpSetDraft(_ notes: String, slide: Int) -> String? {
        if slide == 1 { return "Slide 1 already has speaker notes in the deck." }
        saved[slide] = notes
        return nil
    }
}

@MainActor
final class MCPTests: XCTestCase {
    private func call(_ method: String, _ params: [String: Any] = [:], id: Any = 1, deck: MCPDeck) -> [String: Any]? {
        let msg: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method, "params": params]
        let data = try! JSONSerialization.data(withJSONObject: msg)
        return MCPHandler.handle(data, deck: deck).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    private func toolText(_ response: [String: Any]?) -> String {
        (((response?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
    }

    private func isError(_ response: [String: Any]?) -> Bool {
        (response?["result"] as? [String: Any])?["isError"] as? Bool ?? false
    }

    func testInitializeAgreesOnAVersion() {
        let deck = FakeDeck()
        let r = call("initialize", ["protocolVersion": "2025-06-18"], deck: deck)?["result"] as? [String: Any]
        XCTAssertEqual(r?["protocolVersion"] as? String, "2025-06-18")
        XCTAssertNotNil((r?["capabilities"] as? [String: Any])?["tools"])
        let unknown = call("initialize", ["protocolVersion": "1999-01-01"], deck: deck)?["result"] as? [String: Any]
        XCTAssertEqual(unknown?["protocolVersion"] as? String, "2025-06-18")
    }

    func testNotificationsGetNoAnswer() {
        let note = try! JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "method": "notifications/initialized"])
        XCTAssertNil(MCPHandler.handle(note, deck: FakeDeck()))
    }

    func testListsThreeTools() {
        let tools = (call("tools/list", deck: FakeDeck())?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        XCTAssertEqual(tools?.compactMap { $0["name"] as? String }, ["get_deck", "get_slide_image", "set_speaker_notes"])
    }

    func testGetDeck() throws {
        let text = toolText(call("tools/call", ["name": "get_deck", "arguments": [:]], deck: FakeDeck()))
        let info = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
        XCTAssertEqual(info["presentation"] as? String, "Acme Launch")
        XCTAssertEqual(info["current_slide"] as? Int, 2)
        let slides = try XCTUnwrap(info["slides"] as? [[String: Any]])
        XCTAssertEqual(slides[1]["text"] as? String, "Drafting · Delivery")
    }

    func testSlideImage() {
        let deck = FakeDeck()
        let r = call("tools/call", ["name": "get_slide_image", "arguments": ["slide": 2]], deck: deck)
        let block = ((r?["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first
        XCTAssertEqual(block?["type"] as? String, "image")
        XCTAssertEqual(block?["mimeType"] as? String, "image/png")
        XCTAssertTrue(isError(call("tools/call", ["name": "get_slide_image", "arguments": ["slide": 9]], deck: deck)))
    }

    func testSetNotesKeepsADraftAndNeverReplacesDeckNotes() {
        let deck = FakeDeck()
        let ok = call("tools/call", ["name": "set_speaker_notes", "arguments": ["slide": 2, "notes": "Three shifts."]], deck: deck)
        XCTAssertFalse(isError(ok))
        XCTAssertEqual(deck.saved, [2: "Three shifts."])
        let refused = call("tools/call", ["name": "set_speaker_notes", "arguments": ["slide": 1, "notes": "Other"]], deck: deck)
        XCTAssertTrue(isError(refused))
        XCTAssertTrue(isError(call("tools/call", ["name": "set_speaker_notes", "arguments": ["slide": 2, "notes": " "]], deck: deck)))
    }

    func testNoDeckOpen() {
        let deck = FakeDeck()
        deck.mcpDeckName = nil
        let r = call("tools/call", ["name": "get_deck", "arguments": [:]], deck: deck)
        XCTAssertTrue(isError(r))
        XCTAssertTrue(toolText(r).contains("No presentation is open"))
    }

    func testUnknownMethod() {
        let error = call("resources/list", deck: FakeDeck())?["error"] as? [String: Any]
        XCTAssertEqual(error?["code"] as? Int, -32601)
    }

    // MARK: Claude Desktop config

    func testAddingBemaKeepsOtherServers() throws {
        let existing = #"{"mcpServers":{"files":{"command":"/usr/local/bin/files","args":[]}},"globalShortcut":""}"#
        let out = try ClaudeDesktop.adding(command: "/Applications/Bema.app/Contents/MacOS/Bema", to: Data(existing.utf8))
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        let servers = try XCTUnwrap(root["mcpServers"] as? [String: Any])
        XCTAssertNotNil(servers["files"])
        XCTAssertEqual((servers["bema"] as? [String: Any])?["args"] as? [String], ["--mcp"])
        XCTAssertNotNil(root["globalShortcut"])
        XCTAssertTrue(ClaudeDesktop.isConnected(out, command: "/Applications/Bema.app/Contents/MacOS/Bema"))
        XCTAssertFalse(ClaudeDesktop.isConnected(out, command: "/elsewhere/Bema"))
    }

    func testAddingToAMissingOrBrokenConfig() throws {
        XCTAssertTrue(ClaudeDesktop.isConnected(try ClaudeDesktop.adding(command: "/b", to: nil), command: "/b"))
        XCTAssertThrowsError(try ClaudeDesktop.adding(command: "/b", to: Data("[1,2]".utf8)))
    }
}

final class NoteWriterRenderTests: XCTestCase {
    @MainActor func testRenderNotesWithDraftAndSettings() throws {
        let model = PresenterModel()
        model.deckSlides = [
            SlideInfo(id: 1, title: "Welcome", notes: "Say hello.", hidden: false),
            SlideInfo(id: 2, title: "Three shifts", notes: "", hidden: false),
            SlideInfo(id: 3, title: "Numbers", notes: "", hidden: false),
        ]
        model.drafts = [2: "I see **three shifts** coming.\nDrafting is already solved.\nDelivery is next, and that's where Bema helps."]
        model.goTo(2)
        let draft = VStack(alignment: .leading, spacing: 14) {
            DraftBar(slide: 2, editing: .constant(false), text: .constant(""))
            Text(NoteCues.attributed(model.drafts[2]!, fontSize: 22)).font(.system(size: 22)).foregroundStyle(Theme.textBright)
            WritingRow(progress: NoteWritingProgress(slide: 3, done: 1, total: 2, writer: "Claude"))
        }
        try render(draft.environmentObject(model).padding(24).frame(width: 640).background(Theme.panel), "notes-draft")
        model.setDraft("Welcome, everyone.\nTonight: what AI hasn't touched yet.", for: 1)
        try render(DraftBar(slide: 1, editing: .constant(false), text: .constant("")).environmentObject(model)
            .padding(24).frame(width: 640).background(Theme.panel), "notes-edited")
        try render(DraftBar(slide: 1, editing: .constant(true), text: .constant("")).environmentObject(model)
            .padding(24).frame(width: 640).background(Theme.panel), "notes-editing")
        try render(NoNotesView(slide: 3, fontSize: 22).environmentObject(model).padding(24).frame(width: 640, alignment: .leading)
            .background(Theme.panel), "notes-empty")
        try render(NoteWriterSettingsView(showing: .claudeApp).environmentObject(model), "note-writer-claude-app")
        try render(NoteWriterSettingsView(showing: .local).environmentObject(model), "note-writer-local")
    }

    @MainActor private func render(_ view: some View, _ name: String) throws {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            return XCTFail("render failed")
        }
        try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("bema-\(name).png"))
    }
}

final class SingleInstanceTests: XCTestCase {
    func testDefersToTheEarliestOtherBema() {
        let a = SingleInstance.Instance(pid: 10, bundleURL: URL(fileURLWithPath: "/Applications/Bema.app"), launched: Date(timeIntervalSince1970: 100))
        let b = SingleInstance.Instance(pid: 20, bundleURL: URL(fileURLWithPath: "/Users/sam/Applications/Bema.app"), launched: Date(timeIntervalSince1970: 50))
        let me = SingleInstance.Instance(pid: 30, bundleURL: nil, launched: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(SingleInstance.running(among: [a, b, me], me: 30), b)
        XCTAssertNil(SingleInstance.running(among: [me], me: 30))
        XCTAssertNil(SingleInstance.running(among: [], me: 30))
    }
}

final class DockIconTests: XCTestCase {
    func testInTheDockOnlyWhileThePresenterWindowIsOpen() {
        XCTAssertEqual(DockIcon.policy(presenterWindowOpen: true, menuBarIconOn: true), .regular)
        XCTAssertEqual(DockIcon.policy(presenterWindowOpen: false, menuBarIconOn: true), .accessory)
    }

    func testWithoutTheMenuBarIconBemaStaysInTheDock() {
        XCTAssertEqual(DockIcon.policy(presenterWindowOpen: false, menuBarIconOn: false), .regular)
    }
}
