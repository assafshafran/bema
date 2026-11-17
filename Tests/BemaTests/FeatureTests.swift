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

    @MainActor func testASlideWithoutNotesSaysSoInThePrompter() {
        let p = PrompterModel()
        p.load(slides: [SlideInfo(id: 1, title: "Hello", notes: "Welcome everyone", hidden: false),
                        SlideInfo(id: 2, title: "Three shifts", notes: "  \n", hidden: false),
                        SlideInfo(id: 3, title: "Bye", notes: "Thank you", hidden: false)])
        XCTAssertEqual(p.paragraphs.map(\.slide), [1, 2, 3])
        let placeholder = p.paragraphs[1]
        XCTAssertTrue(placeholder.isSlideStart)
        XCTAssertEqual(placeholder.words.map(\.text), [PrompterModel.noNotesCue])
        // Shown faintly and never matched against speech.
        XCTAssertTrue(placeholder.words.allSatisfy { $0.isPlaceholder && $0.isCue && $0.norm.isEmpty })

        // A deck with no notes at all still shows the "no speaker notes" message instead.
        let empty = PrompterModel()
        empty.load(slides: [SlideInfo(id: 1, title: "Hello", notes: "", hidden: false)])
        XCTAssertTrue(empty.words.isEmpty)
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

    @MainActor func testRenderDisplayChooser() throws {
        let options = [
            DisplayOption(name: "Built-in Retina Display", width: 1512, height: 982, builtIn: true, hasBema: true),
            DisplayOption(name: "Hall Projector", width: 1920, height: 1080, builtIn: false, hasBema: false),
        ]
        func chooser(_ pick: String) -> some View {
            DisplayChooser(options: options, selection: .constant(pick), askEachTime: .constant(true), start: {}, cancel: {})
        }
        try save(chooser("Hall Projector"), "display-chooser")
        try save(chooser("Built-in Retina Display"), "display-chooser-same-screen")
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

    @MainActor func testRenderMenuBarIcon() throws {
        let view = HStack(spacing: 16) {
            Image(nsImage: MenuBarIcon.image).renderingMode(.template).resizable().frame(width: 36, height: 36).foregroundStyle(.black)
            Image(nsImage: MenuBarIcon.image).renderingMode(.template).resizable().frame(width: 18, height: 18).foregroundStyle(.black)
        }
        .padding(12).background(Color(white: 0.93))
        try save(view, "menubar-icon")
        XCTAssertTrue(MenuBarIcon.image.isTemplate)
    }
}

final class SelfViewToggleTests: XCTestCase {
    func testClosesWhenTheWindowIsOnScreen() {
        XCTAssertEqual(SelfViewToggle.action(windowVisible: true), .close)
    }

    func testOpensWhenTheWindowIsNotOnScreen() {
        // Whatever Bema last believed: a window that isn't visible gets opened, never ignored.
        XCTAssertEqual(SelfViewToggle.action(windowVisible: false), .open)
    }
}

final class DeviceChoiceTests: XCTestCase {
    let devices = [DeviceChoice.Device(id: "cam-a", name: "FaceTime HD Camera"),
                   DeviceChoice.Device(id: "cam-b", name: "Desk Camera")]

    func testKeepsThePickedDeviceWhileItIsConnected() {
        XCTAssertEqual(DeviceChoice.resolve(saved: "cam-b", available: devices), "cam-b")
        XCTAssertEqual(DeviceChoice.label(saved: "cam-b", available: devices, defaultName: "FaceTime HD Camera"), "Desk Camera")
    }

    func testFallsBackToTheDefaultWhenThePickedDeviceIsGone() {
        XCTAssertNil(DeviceChoice.resolve(saved: "cam-gone", available: devices))
        XCTAssertEqual(DeviceChoice.label(saved: "cam-gone", available: devices, defaultName: "FaceTime HD Camera"), "FaceTime HD Camera")
    }

    func testNoChoiceMeansTheDefault() {
        XCTAssertNil(DeviceChoice.resolve(saved: nil, available: devices))
        XCTAssertEqual(DeviceChoice.label(saved: nil, available: [], defaultName: nil), "System default")
    }
}

final class SlideSplitTests: XCTestCase {
    func testDraggingDownMakesTheCurrentSlideBiggerByTheDrag() {
        let before = SlideSplit.slideHeight(columnHeight: 1000, share: 0.66)
        let share = SlideSplit.share(start: 0.66, dragY: 100, height: 1000)
        XCTAssertEqual(SlideSplit.slideHeight(columnHeight: 1000, share: share) - before, 100, accuracy: 0.0001)
    }

    func testTheCurrentSlideGetsItsShareOfTheColumn() {
        // An exact height, so changing the share always changes the slide (it used to be only a ceiling).
        let small = SlideSplit.slideHeight(columnHeight: 800, share: 0.4)
        let large = SlideSplit.slideHeight(columnHeight: 800, share: 0.8)
        XCTAssertEqual(small, (800 - SlideSplit.chrome) * 0.4, accuracy: 0.0001)
        XCTAssertEqual(large, small * 2, accuracy: 0.0001)
        XCTAssertEqual(SlideSplit.slideHeight(columnHeight: 800, share: 5), (800 - SlideSplit.chrome) * SlideSplit.range.upperBound, accuracy: 0.0001)
        XCTAssertEqual(SlideSplit.slideHeight(columnHeight: 50, share: 0.66), 60)
    }

    func testStaysWithinLimits() {
        XCTAssertEqual(SlideSplit.share(start: 0.66, dragY: 900, height: 1000), SlideSplit.range.upperBound)
        XCTAssertEqual(SlideSplit.share(start: 0.66, dragY: -900, height: 1000), SlideSplit.range.lowerBound)
        XCTAssertEqual(SlideSplit.share(start: 0.5, dragY: 40, height: 0), 0.5)
    }
}

final class AudienceDisplayTests: XCTestCase {
    let displays = ["Built-in Retina Display", "Hall Projector"]

    func testUsesTheSavedDisplayWhenConnected() {
        XCTAssertEqual(AudienceDisplay.choose(saved: "Built-in Retina Display", displays: displays, presenter: "Built-in Retina Display"),
                       "Built-in Retina Display")
    }

    func testOtherwisePicksADisplayWithoutBema() {
        XCTAssertEqual(AudienceDisplay.choose(saved: "Old TV", displays: displays, presenter: "Built-in Retina Display"), "Hall Projector")
        XCTAssertEqual(AudienceDisplay.choose(saved: "", displays: displays, presenter: "Hall Projector"), "Built-in Retina Display")
    }

    func testOneDisplayIsTheOnlyChoice() {
        XCTAssertEqual(AudienceDisplay.choose(saved: "", displays: ["Built-in Retina Display"], presenter: "Built-in Retina Display"),
                       "Built-in Retina Display")
        XCTAssertNil(AudienceDisplay.choose(saved: "", displays: [], presenter: nil))
    }

    func testAsksOnlyWithAChoiceAndWhenTurnedOn() {
        XCTAssertTrue(AudienceDisplay.shouldAsk(enabled: true, displayCount: 2))
        XCTAssertFalse(AudienceDisplay.shouldAsk(enabled: true, displayCount: 1))
        XCTAssertFalse(AudienceDisplay.shouldAsk(enabled: false, displayCount: 3))
    }
}
