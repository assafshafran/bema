@testable import Bema
import SwiftUI
import XCTest

final class PowerPointButtonDialogTests: XCTestCase {
    private let dialog = "AXDialog"

    func testRecognisesTheBemaDialogHoweverPowerPointTitlesIt() {
        XCTAssertTrue(PowerPointButtonDialog.isBemaDialog(title: "Bema", subrole: dialog))
        XCTAssertTrue(PowerPointButtonDialog.isBemaDialog(title: "Opening Bema…", subrole: dialog))
        XCTAssertTrue(PowerPointButtonDialog.isBemaDialog(title: "Bema - Opening Bema…", subrole: dialog))
    }

    func testLeavesDecksAndOtherWindowsAlone() {
        // A deck called Bema is a document window, not a dialog.
        XCTAssertFalse(PowerPointButtonDialog.isBemaDialog(title: "Bema", subrole: "AXStandardWindow"))
        XCTAssertFalse(PowerPointButtonDialog.isBemaDialog(title: "Bema", subrole: nil))
        XCTAssertFalse(PowerPointButtonDialog.isBemaDialog(title: nil, subrole: dialog))
        XCTAssertFalse(PowerPointButtonDialog.isBemaDialog(title: "", subrole: dialog))
        XCTAssertFalse(PowerPointButtonDialog.isBemaDialog(title: "Bema launch plan", subrole: dialog))
        XCTAssertFalse(PowerPointButtonDialog.isBemaDialog(title: "Acme Plan.pptx", subrole: dialog))
    }

    func testTheDialogPageCarriesTheMarker() throws {
        let page = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("site/office/present.html")
        let html = try String(contentsOf: page, encoding: .utf8)
        let title = try XCTUnwrap(html.range(of: "<title>").flatMap { start in
            html.range(of: "</title>").map { String(html[start.upperBound..<$0.lowerBound]) } })
        XCTAssertTrue(PowerPointButtonDialog.isBemaDialog(title: title, subrole: "AXDialog"))
    }
}

/// The top bar at the window's narrowest and at a roomy width: captions only where they fit.
final class TopBarRenderTests: XCTestCase {
    @MainActor func testTopBarFitsAtTheMinimumWidth() throws {
        _ = NSApplication.shared
        let model = PresenterModel()
        for width in [1320.0, 1700.0] {
            let view = TopBar().environmentObject(model).frame(width: width).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, width, accuracy: 1)
            let png = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?.representation(using: .png, properties: [:]))
            try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("bema-topbar-\(Int(width)).png"))
        }
    }
}

final class PreviewCheckTests: XCTestCase {
    private func slide(_ id: Int, _ title: String, hidden: Bool = false) -> SlideInfo {
        SlideInfo(id: id, title: title, notes: "", hidden: hidden)
    }

    func testPreviewsOfThisDeckMatch() {
        let slides = [slide(1, "The slide\nis the easy part."), slide(2, "AI can write the deck"), slide(3, "")]
        let pages = ["KEYNOTE · THE FUTURE\nThe slide is the\neasy part.", "AI can write\nthe deck. It can't give the talk.", "Thank you"]
        XCTAssertTrue(PreviewCheck.matches(pageTexts: pages, slides: slides))
    }

    func testPreviewsOfAnOlderVersionDoNot() {
        let slides = [slide(1, "The slide is the easy part."), slide(2, "AI can write the deck"), slide(3, "Where the tools are going")]
        let pages = ["Bema sample\nA test deck with speaker notes", "Why a new presenter view", "How it works"]
        XCTAssertFalse(PreviewCheck.matches(pageTexts: pages, slides: slides))
    }

    func testPageCountMustFitTheDeck() {
        let slides = [slide(1, "Acme plan"), slide(2, "Numbers", hidden: true), slide(3, "Next steps")]
        XCTAssertTrue(PreviewCheck.matches(pageTexts: ["Acme plan", "Next steps"], slides: slides))    // hidden slide left out
        XCTAssertTrue(PreviewCheck.matches(pageTexts: ["Acme plan", "Numbers", "Next steps"], slides: slides))
        XCTAssertFalse(PreviewCheck.matches(pageTexts: ["Acme plan"], slides: slides))
    }

    func testSlidesWithoutTitlesCantBeChecked() {
        XCTAssertTrue(PreviewCheck.matches(pageTexts: ["", ""], slides: [slide(1, ""), slide(2, "")]))
    }
}
