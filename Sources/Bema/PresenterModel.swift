import AppKit
import CryptoKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PresenterModel: ObservableObject {
    static let shared = PresenterModel()

    enum Phase: Equatable {
        case empty
        case loading(String)
        case ready        // deck loaded, slideshow not running (you can still browse notes)
        case presenting   // PowerPoint slideshow is running and we follow it
        case failed(String)
    }

    enum AudienceScreen: Equatable { case black, white, normal }

    @Published private(set) var phase: Phase = .empty {
        didSet {
            if oldValue != .presenting && phase == .presenting { CoachModel.shared.showStarted() }
            if oldValue == .presenting && phase != .presenting { CoachModel.shared.showEnded() }
            if (oldValue == .presenting) != (phase == .presenting) {
                VoiceCommands.shared.showChanged()
                Captions.shared.showChanged()
            }
        }
    }
    @Published private(set) var deckURL: URL?
    @Published private(set) var slides: [SlideInfo] = []
    @Published private(set) var current: Int = 1 {
        didSet {
            if oldValue != current {
                clearDrawings()
                PrompterModel.shared.slideChanged(to: current)
                CoachModel.shared.slideChanged(from: oldValue, to: current)
            }
        }
    }
    @Published private(set) var pdf: PDFDocument?
    @Published private(set) var audience: AudienceScreen = .normal
    @Published private(set) var showEnded = false
    @Published private(set) var powerPointReady = false
    @Published var notice: String?
    @Published var showAccessibilityHelp = false

    // Laser pointer and drawing
    @Published var tool: PointerTool = .none {
        didSet { if !tool.followsHover { laserPoint = nil } }
    }
    @Published var laserPoint: CGPoint?
    @Published var strokes: [Stroke] = []
    @Published var activeStroke: Stroke?
    @Published var stamps: [Stamp] = []
    @Published private(set) var ripples: [Ripple] = []
    @Published private(set) var laserTrail: [TrailPoint] = []
    @Published private(set) var reaction: Reaction?
    @Published var laserStyle: LaserStyle = LaserStyle(rawValue: UserDefaults.standard.string(forKey: "laserStyle") ?? "") ?? .dot {
        didSet { UserDefaults.standard.set(laserStyle.rawValue, forKey: "laserStyle") }
    }
    @Published var stampKind: StampKind = StampKind(rawValue: UserDefaults.standard.string(forKey: "stampKind") ?? "") ?? .check {
        didSet { UserDefaults.standard.set(stampKind.rawValue, forKey: "stampKind") }
    }
    private var effectsTimer: Timer?
    /// Where PowerPoint is drawing the slideshow, in screen coordinates.
    @Published private(set) var showFrame: CGRect?
    private let overlay = AudienceOverlay()
    @Published var audienceScreenName: String = UserDefaults.standard.string(forKey: "audienceScreen") ?? "" {
        didSet { UserDefaults.standard.set(audienceScreenName, forKey: "audienceScreen") }
    }
    @Published var alwaysOnTop = false { didSet { applyWindowLevel() } }
    @Published private(set) var recents: [URL] = (UserDefaults.standard.stringArray(forKey: "recents") ?? [])
        .map { URL(fileURLWithPath: $0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }

    /// Planned length of the talk in minutes (0 = no target). The timer shows progress against it.
    @Published var targetMinutes: Int = UserDefaults.standard.object(forKey: "targetMinutes") as? Int ?? 20 {
        didSet { UserDefaults.standard.set(targetMinutes, forKey: "targetMinutes") }
    }
    /// The display the running show is on, and whether it's true full screen there.
    @Published private(set) var presentingOn: String = ""
    @Published private(set) var audienceFullScreen = false
    @Published private(set) var accessibilityGranted = PowerPointController.hasAccessibility
    /// The deck currently open in PowerPoint's front window (offered as "Present …").
    @Published private(set) var openInPowerPoint: URL?
    private var permissionTimer: Timer?

    // Timer
    @Published private(set) var timerStartedAt: Date?
    @Published private(set) var timerAccumulated: TimeInterval = 0

    /// PowerPoint or Keynote, chosen by the deck's file type.
    private(set) var app: SlideshowController = PowerPointController()
    /// The app that has the deck offered on the welcome card ("Open in Keynote").
    @Published private(set) var openInAppName = "PowerPoint"

    init() {
        // Keep the pre-flight check current while the person grants Accessibility in System Settings.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let granted = PowerPointController.hasAccessibility
                if granted != self.accessibilityGranted { self.accessibilityGranted = granted }
                if granted && self.showAccessibilityHelp {
                    self.showAccessibilityHelp = false
                    self.notice = "Accessibility is allowed. End and restart the show to go full screen."
                }
                if self.phase != .presenting { Task { await self.refreshOpenInPowerPoint() } }
            }
        }
    }
    private var pollTask: Task<Void, Never>?
    private var imageCache: [String: NSImage] = [:]

    var deckName: String { deckURL?.deletingPathExtension().lastPathComponent ?? "Bema" }
    var currentSlide: SlideInfo? { slides.first { $0.id == current } }
    var nextSlide: SlideInfo? { slides.first { $0.id > current && !$0.hidden } }
    var visibleCount: Int { slides.filter { !$0.hidden }.count }
    var visiblePosition: Int { slides.filter { !$0.hidden && $0.id <= current }.count }

    static let deckTypes: [UTType] = [
        "org.openxmlformats.presentationml.presentation",
        "org.openxmlformats.presentationml.slideshow",
        "com.microsoft.powerpoint.openxml.presentation.macroenabled",
        "com.apple.keynote.key",
    ].compactMap { UTType($0) }

    // MARK: - Loading

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = Self.deckTypes
        panel.allowsMultipleSelection = false
        panel.message = "Choose a PowerPoint or Keynote presentation"
        if panel.runModal() == .OK, let url = panel.url { load(url) }
    }

    func load(_ url: URL) {
        Task { await loadDeck(url) }
    }

    private func loadDeck(_ url: URL) async {
        if phase == .presenting { await endShow() }
        pollTask?.cancel()
        deckURL = url
        slides = []
        pdf = nil
        imageCache = [:]
        powerPointReady = false
        showEnded = false
        audience = .normal
        notice = nil
        resetTimer()
        addRecent(url)

        app = SlideshowApps.controller(for: url)
        let readsThroughApp = app is KeynoteController

        if !readsThroughApp {
            phase = .loading("Reading speaker notes…")
            do {
                slides = try await Task.detached { try PPTXReader.read(url: url) }.value
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            slidesLoaded(url)
        }

        phase = .loading("Opening in \(app.appName)…")
        do {
            try await app.open(url)
            powerPointReady = true
        } catch {
            if readsThroughApp {
                phase = .failed("\(error.localizedDescription)")
                return
            }
            notice = "\(error.localizedDescription) You can still read your notes, but the slideshow can't start."
            phase = .ready
            return
        }

        if readsThroughApp {
            phase = .loading("Reading presenter notes…")
            do {
                slides = try await app.readSlides() ?? []
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            slidesLoaded(url)
        }

        let cached = Self.previewCacheURL(for: url)
        if !FileManager.default.fileExists(atPath: cached.path) {
            phase = .loading("Preparing slide previews…")
            do { try await app.exportPDF(to: cached) } catch {
                notice = "Slide previews aren't available: \(error.localizedDescription)"
            }
        }
        pdf = PDFDocument(url: cached)
        phase = .ready
        // If this deck's slideshow is already running (e.g. Bema was restarted), pick it back up.
        if case .running(let slide, _, _, _, _) = (try? await app.status()) ?? .notRunning {
            if slide > 0 { current = slide }
            phase = .presenting
            startPolling()
        }
        // Opening the deck brings PowerPoint to the front; come back on top.
        NSApp.activate()
        presenterWindow?.makeKeyAndOrderFront(nil)
    }

    private func slidesLoaded(_ url: URL) {
        current = slides.first { !$0.hidden }?.id ?? 1
        PrompterModel.shared.load(slides: slides)
        CoachModel.shared.deckLoaded(url)
        RemoteServer.shared.deckChanged()
    }

    /// Previews are cached per file path + modification date + size, so an edited deck is re-exported.
    private static func previewCacheURL(for url: URL) -> URL {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let stamp = "\(url.path)|\((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)|\(attrs?[.size] ?? 0)"
        let hash = SHA256.hash(data: Data(stamp.utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("Bema/\(hash).pdf")
    }

    private func addRecent(_ url: URL) {
        var list = recents.filter { $0.path != url.path }
        list.insert(url, at: 0)
        recents = Array(list.prefix(8))
        UserDefaults.standard.set(recents.map(\.path), forKey: "recents")
    }

    private let powerPointWatcher = PowerPointController()
    private let keynoteWatcher = KeynoteController()

    /// The deck in PowerPoint's or Keynote's front window (whichever was used last).
    func refreshOpenInPowerPoint() async {
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        let keynoteFirst = front == KeynoteController.bundleID
            || (front != PowerPointController.bundleID && !SlideshowApps.isRunning(PowerPointController.bundleID))
        var found: (URL, String)?
        for watcher in (keynoteFirst ? [keynoteWatcher, powerPointWatcher] as [SlideshowController] : [powerPointWatcher, keynoteWatcher]) {
            if let url = await watcher.activePresentationURL() { found = (url, watcher.appName); break }
        }
        if found?.0 != openInPowerPoint { openInPowerPoint = found?.0 }
        if let name = found?.1, name != openInAppName { openInAppName = name }
    }

    /// Present the deck that's open in PowerPoint (the global shortcut, the Dock menu, the welcome card).
    func presentOpenDeck() {
        Task {
            await refreshOpenInPowerPoint()
            NSApp.activate()
            presenterWindow?.makeKeyAndOrderFront(nil)
            guard let url = openInPowerPoint else {
                notice = PowerPointController.isRunning || SlideshowApps.isRunning(KeynoteController.bundleID)
                    ? "The deck in front isn't a saved file on this Mac. Save it first, or open it from Finder."
                    : "Neither PowerPoint nor Keynote is running. Open a deck in one of them, or choose one here."
                return
            }
            if url.standardizedFileURL == deckURL?.standardizedFileURL, phase == .ready || phase == .presenting { return }
            load(url)
        }
    }

    func closeDeck() {
        Task {
            if phase == .presenting { await endShow() }
            phase = .empty
            deckURL = nil
            slides = []
            pdf = nil
        }
    }

    // MARK: - Slideshow

    var screens: [NSScreen] { NSScreen.screens }

    /// The display the audience sees: your saved choice, otherwise a display other than the one
    /// showing this window, otherwise the main display.
    func audienceScreen() -> NSScreen {
        if let s = screens.first(where: { $0.localizedName == audienceScreenName }) { return s }
        let presenterScreen = presenterWindow?.screen
        return screens.first { $0 != presenterScreen } ?? screens.first ?? NSScreen.main!
    }

    func startShow() {
        guard powerPointReady, phase == .ready else { return }
        Task {
            let screen = audienceScreen()
            let presenterScreen = presenterWindow?.screen
            let fullScreen = screens.count > 1 && screen != presenterScreen
            if fullScreen && !PowerPointController.hasAccessibility {
                PowerPointController.requestAccessibility()
            }
            do {
                showEnded = false
                audience = .normal
                let ok = try await app.startShow(on: screen, from: current, fullScreen: fullScreen)
                presentingOn = screen.localizedName
                audienceFullScreen = fullScreen && ok
                phase = .presenting
                if timerStartedAt == nil { toggleTimer() }
                if !fullScreen && screens.count == 1 {
                    notice = "Only one display is connected, so the slideshow is in a window for rehearsal."
                } else if !ok {
                    notice = "Full screen without a title bar needs Accessibility permission. If Bema is already listed there, select it, remove it with the – button and add it again (the old entry belongs to an earlier build). Then end and restart the show."
                    showAccessibilityHelp = true
                } else {
                    showAccessibilityHelp = false
                }
                startPolling()
                // PowerPoint takes focus when the show starts; take it back so the keyboard and clicker reach us.
                try? await Task.sleep(nanoseconds: 700_000_000)
                NSApp.activate()
                presenterWindow?.makeKeyAndOrderFront(nil)
            } catch {
                notice = error.localizedDescription
            }
        }
    }

    func endShow() async {
        pollTask?.cancel()
        try? await app.endShow()
        if phase == .presenting { phase = .ready }
        tool = .none
        updateOverlay()
        audience = .normal
        showEnded = false
        if timerStartedAt != nil { toggleTimer() }
    }

    func endShowButton() { Task { await endShow() } }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    private func refresh() async {
        guard phase == .presenting else { return }
        guard let status = try? await app.status() else { return }
        switch status {
        case .running(let slide, let black, let white, let done, let frame):
            if slide > 0 && slide != current { current = slide }
            if app.supportsScreenStates { audience = black ? .black : (white ? .white : .normal) }
            showEnded = done
            if let frame {
                showFrame = frame
                // Work out which display the show is on (needed after reconnecting to a running show).
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) {
                    if presentingOn != screen.localizedName { presentingOn = screen.localizedName }
                    let full = abs(frame.width - screen.frame.width) < 2 && abs(frame.height - screen.frame.height) < 2
                    if audienceFullScreen != full { audienceFullScreen = full }
                }
            }
            updateOverlay()
        case .notRunning:
            pollTask?.cancel()
            phase = .ready
            updateOverlay()
            showEnded = false
            audience = .normal
        case .presentationClosed:
            pollTask?.cancel()
            phase = .ready
            updateOverlay()
            powerPointReady = false
            notice = "The presentation was closed in \(app.appName). Open it again to present."
        }
    }

    // MARK: - Navigation

    func next() {
        if phase == .presenting {
            Task { try? await app.next(); await refresh() }
        } else if let n = nextSlide {
            current = n.id
        }
    }

    func previous() {
        if phase == .presenting {
            Task { try? await app.previous(); await refresh() }
        } else if let p = slides.last(where: { $0.id < current && !$0.hidden }) {
            current = p.id
        }
    }

    func goTo(_ id: Int) {
        guard slides.contains(where: { $0.id == id }) else { return }
        if phase == .presenting {
            current = id
            Task { try? await app.goTo(id); await refresh() }
        } else {
            current = id
        }
    }

    func first() { if let s = slides.first(where: { !$0.hidden }) { goTo(s.id) } }
    func last() { if let s = slides.last(where: { !$0.hidden }) { goTo(s.id) } }

    func toggleBlack() { setAudience(audience == .black ? .normal : .black) }
    func toggleWhite() { setAudience(audience == .white ? .normal : .white) }

    private func setAudience(_ state: AudienceScreen) {
        guard phase == .presenting else { return }
        audience = state
        let s: PowerPointController.ScreenState = state == .black ? .black : (state == .white ? .white : .running)
        Task { try? await app.setScreen(s); await refresh() }
    }

    // MARK: - Keyboard and clicker

    /// Returns true if the key was handled. Clickers usually send Page Up / Page Down, arrows or B.
    func handleKey(_ event: NSEvent) -> Bool {
        guard phase == .ready || phase == .presenting else { return false }
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        switch event.keyCode {
        case 124, 125, 49, 121, 36, 76: next(); return true          // → ↓ space PgDn return enter
        case 123, 126, 116, 51: previous(); return true               // ← ↑ PgUp delete
        case 115: first(); return true                                // Home
        case 119: last(); return true                                 // End
        case 53:                                                      // Esc
            if tool != .none { tool = .none; return true }
            if phase == .presenting { endShowButton(); return true }
            return false
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "b", ".": toggleBlack(); return true
        case "w", ",": toggleWhite(); return true
        case "l": tool = tool == .laser ? .none : .laser; return true
        case "s": tool = tool == .spotlight ? .none : .spotlight; return true
        case "m": tool = tool == .magnifier ? .none : .magnifier; return true
        case "t": tool = tool == .stamp ? .none : .stamp; return true
        case "1": fireReaction(.confetti); return true
        case "2": fireReaction(.applause); return true
        case "3": fireReaction(.hearts); return true
        case "p": tool = tool == .pen ? .none : .pen; return true
        case "h": tool = tool == .highlighter ? .none : .highlighter; return true
        case "e", "c": clearDrawings(); return true
        default: return false
        }
    }

    // MARK: - Laser pointer and drawing

    /// True while something on the slide is moving (trail, ripple, reaction), so the canvas animates.
    var effectsAnimating: Bool {
        !ripples.isEmpty || reaction != nil || (tool == .laser && laserStyle.usesTrail && !laserTrail.isEmpty)
    }

    func movePointer(to p: CGPoint) {
        laserPoint = p
        if tool == .laser && laserStyle.usesTrail {
            laserTrail.append(TrailPoint(point: p, time: Date()))
            if laserTrail.count > 40 { laserTrail.removeFirst(laserTrail.count - 40) }
            startEffectsTimer()
        }
    }

    func addRipple(at p: CGPoint) {
        ripples.append(Ripple(point: p, start: Date()))
        startEffectsTimer()
    }

    func placeStamp(at p: CGPoint) {
        stamps.append(Stamp(kind: stampKind, point: p))
    }

    func fireReaction(_ kind: ReactionKind) {
        reaction = Reaction(kind: kind, start: Date(), seed: UInt64.random(in: 1...UInt64.max / 2))
        startEffectsTimer()
    }

    /// Clears finished ripples, old trail points and finished reactions; stops when nothing is moving.
    private func startEffectsTimer() {
        guard effectsTimer == nil else { return }
        effectsTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                let now = Date()
                let liveRipples = self.ripples.filter { now.timeIntervalSince($0.start) < 0.7 }
                if liveRipples.count != self.ripples.count { self.ripples = liveRipples }
                let liveTrail = self.laserTrail.filter { now.timeIntervalSince($0.time) < 0.6 }
                if liveTrail.count != self.laserTrail.count { self.laserTrail = liveTrail }
                if let r = self.reaction, now.timeIntervalSince(r.start) > r.kind.duration { self.reaction = nil }
                if self.ripples.isEmpty && self.laserTrail.isEmpty && self.reaction == nil {
                    timer.invalidate()
                    self.effectsTimer = nil
                }
            }
        }
    }

    func commitStroke() {
        if let s = activeStroke, s.points.count > 0 { strokes.append(s) }
        activeStroke = nil
    }

    func clearDrawings() {
        strokes = []
        stamps = []
        activeStroke = nil
    }

    /// The slide's rectangle inside the slideshow area (PowerPoint letterboxes it to keep its shape).
    private func slideRect(in area: CGRect) -> CGRect {
        let aspect = slideAspect
        var w = area.width, h = area.width / aspect
        if h > area.height { h = area.height; w = h * aspect }
        return CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
    }

    private func updateOverlay() {
        if phase == .presenting, audience == .normal || !app.supportsScreenStates, !showEnded, let frame = showFrame {
            overlay.show(over: slideRect(in: frame), model: self)
        } else {
            overlay.hide()
        }
    }

    // MARK: - Timer

    func elapsed(at date: Date) -> TimeInterval {
        timerAccumulated + (timerStartedAt.map { date.timeIntervalSince($0) } ?? 0)
    }

    func toggleTimer() {
        if let start = timerStartedAt {
            timerAccumulated += Date().timeIntervalSince(start)
            timerStartedAt = nil
        } else {
            timerStartedAt = Date()
        }
    }

    func resetTimer() {
        timerAccumulated = 0
        timerStartedAt = phase == .presenting ? Date() : nil
    }

    // MARK: - Slide images

    /// The PDF has one page per slide, or one per visible slide if PowerPoint left hidden slides out.
    private func pageIndex(for id: Int) -> Int? {
        guard let pdf else { return nil }
        if pdf.pageCount == slides.count { return id - 1 }
        let visible = slides.filter { !$0.hidden }
        return visible.firstIndex { $0.id == id }.flatMap { $0 < pdf.pageCount ? $0 : nil }
    }

    func image(for id: Int, width points: CGFloat) -> NSImage? {
        guard let pdf, let idx = pageIndex(for: id), let page = pdf.page(at: idx) else { return nil }
        let scale = presenterWindow?.backingScaleFactor ?? 2
        let bucket = max(200, (Int(points * scale) / 200 + 1) * 200)
        let key = "\(id)-\(bucket)"
        if let img = imageCache[key] { return img }
        let bounds = page.bounds(for: .cropBox)
        let size = NSSize(width: CGFloat(bucket), height: CGFloat(bucket) * bounds.height / max(bounds.width, 1))
        let img = page.thumbnail(of: size, for: .cropBox)
        if imageCache.count > 80 { imageCache.removeAll() }
        imageCache[key] = img
        return img
    }

    var slideAspect: CGFloat {
        guard let page = pdf?.page(at: 0) else { return 16.0 / 9.0 }
        let b = page.bounds(for: .cropBox)
        return b.width / max(b.height, 1)
    }

    // MARK: - Window

    var presenterWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true && $0.isVisible }
            ?? NSApp.windows.first { $0.isVisible && $0.canBecomeMain }
    }

    private func applyWindowLevel() {
        presenterWindow?.level = alwaysOnTop ? .floating : .normal
    }

    /// Dark, seamless title bar that blends into the top bar.
    func styleWindow() {
        guard let w = presenterWindow else { return }
        w.titlebarAppearsTransparent = true
        w.backgroundColor = Theme.nsBar
        w.appearance = NSAppearance(named: .darkAqua)
    }

    var targetSeconds: TimeInterval { TimeInterval(targetMinutes * 60) }
}
