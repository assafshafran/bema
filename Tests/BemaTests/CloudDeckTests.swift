import XCTest
@testable import Bema

final class CloudDeckTests: XCTestCase {
    func testWebAddressesAreCloudDecks() {
        let url = CloudDeck.url(fromFullName: "https://acme.example.com/sites/Team/Shared%20Documents/Launch.pptx")
        XCTAssertNotNil(url)
        XCTAssertTrue(CloudDeck.isCloud(url!))
        XCTAssertEqual(url!.deletingPathExtension().lastPathComponent, "Launch")
    }

    func testAddressWithSpacesIsStillRead() {
        let url = CloudDeck.url(fromFullName: "https://acme.example.com/sites/Team/Shared Documents/Q3 Plan.pptx")
        XCTAssertNotNil(url)
        XCTAssertEqual(url?.host, "acme.example.com")
        XCTAssertEqual(url?.deletingPathExtension().lastPathComponent, "Q3 Plan")
    }

    func testFilesAndUnsavedDecksAreNotCloudDecks() {
        XCTAssertNil(CloudDeck.url(fromFullName: "/Users/sam/Decks/Launch.pptx"))
        XCTAssertNil(CloudDeck.url(fromFullName: "Presentation1"))
        XCTAssertNil(CloudDeck.url(fromFullName: ""))
        XCTAssertFalse(CloudDeck.isCloud(URL(fileURLWithPath: "/Users/sam/Decks/Launch.pptx")))
    }

    func testKeyKeepsFilePathsAndUsesTheAddressForCloudDecks() {
        XCTAssertEqual(CloudDeck.key(URL(fileURLWithPath: "/Users/sam/Decks/Launch.pptx")), "/Users/sam/Decks/Launch.pptx")
        let cloud = URL(string: "https://acme.example.com/sites/Team/Launch.pptx")!
        XCTAssertEqual(CloudDeck.key(cloud), "https://acme.example.com/sites/Team/Launch.pptx")
    }

    func testFullNameCandidatesIncludeTheDecodedSpelling() {
        let url = URL(string: "https://acme.example.com/Shared%20Documents/Launch.pptx")!
        XCTAssertEqual(CloudDeck.fullNameCandidates(url), [
            "https://acme.example.com/Shared%20Documents/Launch.pptx",
            "https://acme.example.com/Shared Documents/Launch.pptx",
        ])
        let plain = URL(string: "https://acme.example.com/Launch.pptx")!
        XCTAssertEqual(CloudDeck.fullNameCandidates(plain), ["https://acme.example.com/Launch.pptx"])
    }

    func testParsesPowerPointsSlideRecords() {
        let rs = "\u{1E}", us = "\u{1F}"
        let out = "1\(us)false\(us)Welcome\u{0B}to Acme\(us)Say hello.\rThen the agenda.\(rs)"
            + "2\(us)true\(us)\(us)\(rs)"
            + "3\(us)false\(us)Numbers\(us)Noa has the figures.\(rs)\n"
        let slides = CloudDeck.parseSlides(out)
        XCTAssertEqual(slides, [
            SlideInfo(id: 1, title: "Welcome", notes: "Say hello.\nThen the agenda.", hidden: false),
            SlideInfo(id: 2, title: "", notes: "", hidden: true),
            SlideInfo(id: 3, title: "Numbers", notes: "Noa has the figures.", hidden: false),
        ])
    }

    func testMalformedRecordsAreSkipped() {
        XCTAssertEqual(CloudDeck.parseSlides("garbage\u{1E}\n"), [])
        XCTAssertEqual(CloudDeck.parseSlides(""), [])
    }
}
