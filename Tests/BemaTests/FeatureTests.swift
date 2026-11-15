import SwiftUI
import XCTest
@testable import Bema

final class VoiceCommandTests: XCTestCase {
    private func words(_ s: String) -> [String] { ScriptText.tokens(s).map(ScriptText.normalize) }

    @MainActor func testBasicCommands() {
        XCTAssertEqual(VoiceCommands.parse(words("okay next slide please"), final: false), .next)
        XCTAssertEqual(VoiceCommands.parse(words("let's go back for a second"), final: false), .previous)
        XCTAssertEqual(VoiceCommands.parse(words("black screen"), final: false), .black)
        XCTAssertEqual(VoiceCommands.parse(words("go to slide five"), final: false), .slide(5))
        XCTAssertEqual(VoiceCommands.parse(words("slide number 12"), final: false), .slide(12))
        XCTAssertEqual(VoiceCommands.parse(words("השקופית הבאה"), final: false), .next)
    }

    @MainActor func testTitleOnlyWhenFinal() {
        XCTAssertNil(VoiceCommands.parse(words("go to pricing"), final: false))
        XCTAssertEqual(VoiceCommands.parse(words("go to pricing"), final: true), .title("pricing"))
    }

    @MainActor func testOrdinarySpeechIsNotACommand() {
        XCTAssertNil(VoiceCommands.parse(words("the next quarter will show the slide in revenue"), final: true))
    }

    @MainActor func testTitleMatch() {
        let slides = [SlideInfo(id: 1, title: "Welcome", notes: "", hidden: false),
                      SlideInfo(id: 2, title: "Pricing and plans", notes: "", hidden: false),
                      SlideInfo(id: 3, title: "Roadmap", notes: "", hidden: false)]
        XCTAssertEqual(VoiceCommands.bestTitleMatch("pricing", in: slides)?.id, 2)
        XCTAssertEqual(VoiceCommands.bestTitleMatch("the roadmap", in: slides)?.id, 3)
        XCTAssertNil(VoiceCommands.bestTitleMatch("budget", in: slides))
    }
}

final class NoteCueTests: XCTestCase {
    @MainActor func testPlainStripsMarkup() {
        XCTAssertEqual(NoteCues.plain("Hello [pause] **world**"), "Hello world")
    }

    @MainActor func testAttributedTurnsCuesIntoChips() {
        let a = NoteCues.attributed("Wait [look up] then **go**", fontSize: 20)
        let text = String(a.characters)
        XCTAssertTrue(text.contains("LOOK UP"))
        XCTAssertFalse(text.contains("**"))
    }

    @MainActor func testPrompterKeepsCuesOutOfMatching() {
        let p = PrompterModel()
        p.load(slides: [SlideInfo(id: 1, title: "", notes: "Welcome [smile] to **the big** show [look up]", hidden: false)])
        let cues = p.words.filter(\.isCue)
        XCTAssertEqual(cues.map(\.text), ["SMILE", "LOOK UP"])
        XCTAssertTrue(cues.allSatisfy { $0.norm.isEmpty })
        XCTAssertEqual(p.words.filter(\.bold).map(\.text), ["the", "big"])
    }
}

final class PollAndRemoteTests: XCTestCase {
    @MainActor func testOneVotePerPhone() {
        let poll = PollModel()
        poll.setOptions(["A", "B"])
        poll.vote(option: 0, voter: "phone1")
        poll.vote(option: 1, voter: "phone2")
        poll.vote(option: 1, voter: "phone1")   // changes vote
        poll.vote(option: 5, voter: "phone3")   // out of range, ignored
        XCTAssertEqual(poll.votes, [0, 2])
        XCTAssertEqual(poll.totalVotes, 2)
    }

    func testParsesRequestHead() throws {
        let req = try XCTUnwrap(HTTPRequest(Data("POST /r/abc/cmd?c=next HTTP/1.1\r\nHost: x\r\n\r\n".utf8)))
        XCTAssertEqual(req.method, "POST")
        XCTAssertEqual(req.path, "/r/abc/cmd")
        XCTAssertEqual(req.query["c"], "next")
        XCTAssertNil(HTTPRequest(Data("GET / HTTP/1.1\r\nHost: x".utf8)))   // incomplete
    }

    @MainActor func testRemoteServerAnswersOnlyWithTheSecret() async throws {
        let server = RemoteServer.shared
        server.remoteEnabled = true
        for _ in 0..<50 where server.port == nil { try await Task.sleep(nanoseconds: 100_000_000) }
        let port = try XCTUnwrap(server.port)
        let ok = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/r/\(server.remoteToken)/state")!)
        XCTAssertEqual((ok.1 as? HTTPURLResponse)?.statusCode, 200)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: ok.0) as? [String: Any])
        XCTAssertNotNil(json["position"])
        let page = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/r/\(server.remoteToken)")!)
        XCTAssertTrue(String(decoding: page.0, as: UTF8.self).contains("Bema remote"))
        let bad = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/r/wrongtoken/state")!)
        XCTAssertEqual((bad.1 as? HTTPURLResponse)?.statusCode, 404)
        server.remoteEnabled = false
    }

    @MainActor func testQRCode() {
        XCTAssertNotNil(RemoteServer.qrCode(for: "http://192.168.1.2:8765/r/abc"))
    }
}

/// Renders views to PNGs in $TMPDIR for a visual check.
final class FeatureRenderTests: XCTestCase {
    @MainActor private func save<V: View>(_ view: V, _ name: String) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        let rep = try XCTUnwrap(NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation)))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bema-\(name).png")
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: url)
        print("Rendered \(url.path)")
    }

    @MainActor func testRenderEffects() throws {
        let model = PresenterModel()
        func slide(_ tool: PointerTool, _ style: LaserStyle = .dot) -> some View {
            ZStack {
                Rectangle().fill(.white)
                VStack(alignment: .leading, spacing: 10) {
                    Text("Quarterly results").font(.system(size: 26, weight: .bold))
                    Text("• Revenue up 12%\n• Three new markets\n• Churn down").font(.system(size: 16))
                }.foregroundStyle(.black).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(24)
                AnnotationCanvas()
            }
            .frame(width: 400, height: 225)
        }
        model.stamps = [Stamp(kind: .check, point: CGPoint(x: 0.75, y: 0.35)), Stamp(kind: .wow, point: CGPoint(x: 0.82, y: 0.72)),
                        Stamp(kind: .ring, point: CGPoint(x: 0.3, y: 0.42))]
        model.strokes = [Stroke(tool: .highlighter, points: [CGPoint(x: 0.07, y: 0.36), CGPoint(x: 0.42, y: 0.36)])]
        model.tool = .spotlight
        model.laserPoint = CGPoint(x: 0.35, y: 0.55)
        try save(slide(.spotlight).environmentObject(model), "spotlight")
        model.tool = .laser
        model.laserStyle = .hand
        model.laserPoint = CGPoint(x: 0.35, y: 0.55)
        try save(slide(.laser).environmentObject(model), "hand")
    }

    @MainActor func testRenderReport() throws {
        let report = TalkReport(date: Date(), deck: "Sample", total: 512, target: 600,
                                slides: [SlideTiming(id: 1, title: "Welcome", seconds: 42, budget: 60, words: 90),
                                         SlideTiming(id: 2, title: "Why a new presenter view", seconds: 130, budget: 90, words: 300),
                                         SlideTiming(id: 3, title: "How it works", seconds: 95, budget: 100, words: 220)],
                                words: 610, fillers: ["um": 4, "like": 3, "you know": 1], rehearsal: true)
        try save(TalkReportView(report: report).environmentObject(PresenterModel()), "report")
    }
}
