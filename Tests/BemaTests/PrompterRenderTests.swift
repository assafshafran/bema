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
}
