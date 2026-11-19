import SwiftUI
import XCTest
@testable import Bema

final class QuickPromptTests: XCTestCase {
    func testSummarySaysWhatHappensThenHowLong() {
        XCTAssertTrue(QuickPrompt.summary(for: "  \n").hasPrefix("Remembered on this Mac only"))
        XCTAssertEqual(QuickPrompt.summary(for: "Hello"), "1 word · about 1 min at a speaking pace")
        let speech = Array(repeating: "word", count: 420).joined(separator: " ")
        XCTAssertEqual(QuickPrompt.summary(for: speech), "420 words · about 3 min at a speaking pace")
    }

    func testRightClickOnlyOnTheMenuBarItem() {
        XCTAssertTrue(MenuBarRightClick.isStatusBarWindow(className: "NSStatusBarWindow"))
        XCTAssertFalse(MenuBarRightClick.isStatusBarWindow(className: "NSWindow"))
        XCTAssertFalse(MenuBarRightClick.isStatusBarWindow(className: "SwiftUI.AppKitWindow"))
    }

    /// Writes $TMPDIR/bema-quick-prompt.png. (The text box itself doesn't draw in an offscreen render.)
    @MainActor func testRendersTheCard() throws {
        _ = NSApplication.shared
        let view = QuickPromptCard().frame(width: 640).padding(24).background(Theme.ground).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            .write(to: FileManager.default.temporaryDirectory.appendingPathComponent("bema-quick-prompt.png"))
    }
}
