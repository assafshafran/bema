import SwiftUI
import XCTest
@testable import Bema

/// Renders the prompter script to an image so RTL layout can be checked by eye.
/// Writes $TMPDIR/bema-prompter-rtl.png.
final class PrompterRenderTests: XCTestCase {
    @MainActor
    func testRendersRightToLeftScript() throws {
        let prompter = PrompterModel()
        prompter.load(slides: [
            // Made-up Hebrew notes followed by an English line.
            SlideInfo(id: 1, title: "סיכום", notes: "סיכום ראשון – הצוות בנה כלי חדש שעוזר למציגים לדבר בביטחון.\nThe second line is English.", hidden: false)
        ])
        let view = ScriptBody(paragraphs: prompter.paragraphs, current: 3, fontSize: 28) { _ in }
            .frame(width: 520)
            .padding(20)
            .background(Theme.panel)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bema-prompter-rtl.png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("Rendered \(url.path)")
        XCTAssertTrue(prompter.paragraphs[0].rtl)
        XCTAssertFalse(prompter.paragraphs[1].rtl)
    }

    /// Writes $TMPDIR/bema-prompter-no-notes.png: a slide without notes between two with notes.
    @MainActor
    func testRendersASlideWithoutNotes() throws {
        let prompter = PrompterModel()
        prompter.load(slides: [
            SlideInfo(id: 2, title: "Acme today", notes: "Here is the thing. Nobody can give the talk for you.", hidden: false),
            SlideInfo(id: 3, title: "Three shifts", notes: "", hidden: false),
            SlideInfo(id: 4, title: "How we got here", notes: "We went from a clicker to a prompter that listens.", hidden: false)
        ])
        let view = ScriptBody(paragraphs: prompter.paragraphs, current: 4, fontSize: 28) { _ in }
            .frame(width: 520, height: 520, alignment: .top)
            .padding(20)
            .background(Theme.panel)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bema-prompter-no-notes.png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        XCTAssertTrue(prompter.paragraphs[1].words[0].isPlaceholder)
    }

    /// Writes $TMPDIR/bema-prompter-own-text.png (the paste box) and bema-prompter-own-script.png (prompting it).
    @MainActor
    func testRendersOwnTextBoxAndScript() throws {
        UserDefaults.standard.set("Good evening, Acme. Tonight Noa and I will walk you through the plan.", forKey: PrompterModel.ownScriptKey)
        defer { UserDefaults.standard.removeObject(forKey: PrompterModel.ownScriptKey) }
        _ = NSApplication.shared
        let prompter = PrompterModel()
        try render(OwnScriptEditor(prompter: prompter).frame(width: 640, height: 300), "bema-prompter-own-text.png")

        prompter.useOwnScript("Good evening, Acme.\nTonight Noa and I will walk you through the plan.")
        try render(ScriptBody(paragraphs: prompter.paragraphs, current: 2, fontSize: 28) { _ in }
            .frame(width: 520, height: 260, alignment: .top), "bema-prompter-own-script.png")
        XCTAssertTrue(prompter.paragraphs.allSatisfy { $0.slide == 0 })
    }

    @MainActor
    private func render(_ content: some View, _ name: String) throws {
        let view = content.padding(20).background(Theme.panel).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: FileManager.default.temporaryDirectory.appendingPathComponent(name))
    }
}
