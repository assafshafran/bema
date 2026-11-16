import AppKit
import ApplicationServices

/// The presentation app that runs the slideshow for the audience: PowerPoint or Keynote.
/// Everything else in Bema (presenter window, prompter, pointer tools, coach) works the same with either.
protocol SlideshowController: AnyObject {
    var appName: String { get }
    var bundleID: String { get }
    /// Whether the app can black or white out the screen itself. Otherwise Bema draws it on its overlay.
    var supportsScreenStates: Bool { get }

    func open(_ url: URL) async throws
    /// Titles and notes read through the app, or nil when Bema reads them from the file itself.
    func readSlides() async throws -> [SlideInfo]?
    func exportPDF(to pdfURL: URL) async throws
    @discardableResult
    func startShow(on screen: NSScreen, from slide: Int, fullScreen: Bool) async throws -> Bool
    func next() async throws
    func previous() async throws
    func goTo(_ slide: Int) async throws
    func setScreen(_ state: PowerPointController.ScreenState) async throws
    func endShow() async throws
    func status() async throws -> ShowStatus
    /// The deck in the app's front window: a file on this Mac, or (PowerPoint) the web address of a deck
    /// opened from OneDrive, SharePoint or Teams. Never launches the app.
    func activePresentationURL() async -> URL?
}

extension PowerPointController: SlideshowController {
    var appName: String { "PowerPoint" }
    var bundleID: String { Self.bundleID }
    var supportsScreenStates: Bool { true }
}

enum SlideshowApps {
    static let keynoteExtensions: Set<String> = ["key"]
    static let powerPointExtensions: Set<String> = ["pptx", "ppsx", "pptm"]
    static var allExtensions: Set<String> { keynoteExtensions.union(powerPointExtensions) }

    static func controller(for url: URL) -> SlideshowController {
        keynoteExtensions.contains(url.pathExtension.lowercased()) ? KeynoteController() : PowerPointController()
    }

    static func isRunning(_ bundleID: String) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}

// MARK: - AppleScript runner

/// Runs AppleScript on one serial queue (NSAppleScript should only be used from a single thread).
final class ScriptRunner {
    private let queue: DispatchQueue
    let appName: String

    init(label: String, appName: String) {
        queue = DispatchQueue(label: label)
        self.appName = appName
    }

    @discardableResult
    func run(_ source: String) async throws -> String {
        let appName = self.appName
        return try await withCheckedThrowingContinuation { cont in
            queue.async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let msg = error[NSAppleScript.errorMessage] as? String ?? "\(appName) reported an error."
                    let code = error[NSAppleScript.errorNumber] as? Int ?? 0
                    if code == -1743 {
                        cont.resume(throwing: PowerPointError.script(
                            "Bema isn't allowed to control \(appName). Turn it on in System Settings → Privacy & Security → Automation."))
                    } else if code == -1712 {
                        cont.resume(throwing: PowerPointError.script(
                            "\(appName) didn't respond. If it's showing a welcome screen or a dialog, close it and try again."))
                    } else {
                        cont.resume(throwing: PowerPointError.script("\(msg) (\(code))"))
                    }
                } else {
                    cont.resume(returning: result?.stringValue ?? "")
                }
            }
        }
    }
}

// MARK: - Accessibility helpers

enum AX {
    static func app(_ bundleID: String) -> AXUIElement? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier else { return nil }
        return AXUIElementCreateApplication(pid)
    }

    static func attribute<T>(_ el: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func windows(_ app: AXUIElement) -> [AXUIElement] {
        attribute(app, kAXWindowsAttribute) ?? []
    }

    static func frame(of window: AXUIElement) -> CGRect? {
        guard let posValue: AXValue = attribute(window, kAXPositionAttribute),
              let sizeValue: AXValue = attribute(window, kAXSizeAttribute) else { return nil }
        var pos = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(posValue, .cgPoint, &pos)
        AXValueGetValue(sizeValue, .cgSize, &size)
        return CGRect(origin: pos, size: size)   // top-left origin, main display
    }

    static func setFrame(of window: AXUIElement, to rect: CGRect) {
        var pos = rect.origin, size = rect.size
        if let p = AXValueCreate(.cgPoint, &pos) { AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, p) }
        if let s = AXValueCreate(.cgSize, &size) { AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, s) }
    }

    static func setFullScreen(_ window: AXUIElement, _ on: Bool) -> Bool {
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, on ? kCFBooleanTrue : kCFBooleanFalse) == .success
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool {
        (attribute(window, "AXFullScreen") as Bool?) ?? false
    }

    /// Presses a menu item by its titles, e.g. ["Play", "Play Slideshow in Window"].
    @discardableResult
    static func pressMenu(_ app: AXUIElement, _ path: [String]) -> Bool {
        guard let bar: AXUIElement = attribute(app, kAXMenuBarAttribute) else { return false }
        var current = bar
        for (i, title) in path.enumerated() {
            let children: [AXUIElement] = attribute(current, kAXChildrenAttribute) ?? []
            guard let item = children.first(where: { (attribute($0, kAXTitleAttribute) as String?) == title }) else { return false }
            if i == path.count - 1 {
                return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
            }
            let menus: [AXUIElement] = attribute(item, kAXChildrenAttribute) ?? []
            guard let menu = menus.first else { return false }
            current = menu
        }
        return false
    }

    /// AppKit-style frame (bottom-left origin) from an AX frame (top-left origin on the main display).
    static func cocoaFrame(_ r: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
    }

    static func axFrame(_ r: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        return CGRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
    }
}

// MARK: - Keynote

/// Drives Apple Keynote. Slides and presenter notes are read through Keynote; the show plays in a window
/// that Bema places on the audience display and makes full screen (Accessibility), so Keynote's own
/// presenter display never covers Bema.
final class KeynoteController: SlideshowController {
    static let bundleID = "com.apple.Keynote"
    var appName: String { "Keynote" }
    var bundleID: String { Self.bundleID }
    var supportsScreenStates: Bool { false }

    private let runner = ScriptRunner(label: "Bema.Keynote", appName: "Keynote")
    private var documentName = ""
    private var showWindow: AXUIElement?
    private var usingWindowedShow = false

    private var doc: String { "document " + PowerPointController.quote(documentName) }
    private let tellKeynote = "tell application id \"com.apple.Keynote\""

    static var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }

    func open(_ url: URL) async throws {
        guard Self.isInstalled else { throw PowerPointError.script("Keynote isn't installed.") }
        let path = PowerPointController.quote(url.path)
        let name = try await runner.run("""
        \(tellKeynote)
            set target to \(path)
            repeat with d in documents
                try
                    if POSIX path of ((file of d) as alias) is target then return name of d
                end try
            end repeat
            open POSIX file target
            delay 0.3
            repeat 40 times
                repeat with d in documents
                    try
                        if POSIX path of ((file of d) as alias) is target then return name of d
                    end try
                end repeat
                delay 0.25
            end repeat
            return name of front document
        end tell
        """)
        guard !name.isEmpty else { throw PowerPointError.timeout("opening the deck in Keynote") }
        documentName = name
    }

    func readSlides() async throws -> [SlideInfo]? {
        let out = try await runner.run("""
        \(tellKeynote)
            set d to \(doc)
            set rs to character id 30
            set us to character id 31
            set out to ""
            repeat with s in slides of d
                set t to ""
                try
                    if title showing of s then set t to (object text of default title item of s) as text
                end try
                set n to ""
                try
                    set n to (presenter notes of s) as text
                end try
                set out to out & ((slide number of s) as text) & us & ((skipped of s) as text) & us & t & us & n & rs
            end repeat
            return out
        end tell
        """)
        let slides = out.split(separator: "\u{1E}", omittingEmptySubsequences: true).compactMap { record -> SlideInfo? in
            let f = record.split(separator: "\u{1F}", maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, let n = Int(f[0]) else { return nil }
            return SlideInfo(id: n, title: f[2].trimmingCharacters(in: .whitespacesAndNewlines),
                             notes: f[3].replacingOccurrences(of: "\r", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines),
                             hidden: f[1] == "true")
        }
        if slides.isEmpty { throw PPTXError.unreadable("Keynote reported no slides.") }
        return slides
    }

    func exportPDF(to pdfURL: URL) async throws {
        try FileManager.default.createDirectory(at: pdfURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: pdfURL)
        try await runner.run("""
        \(tellKeynote)
            export \(doc) to (POSIX file \(PowerPointController.quote(pdfURL.path))) as PDF with properties {skipped slides:true}
        end tell
        """)
    }

    func startShow(on screen: NSScreen, from slide: Int, fullScreen: Bool) async throws -> Bool {
        // Start on the right slide.
        try? await runner.run("""
        \(tellKeynote)
            set current slide of \(doc) to slide \(slide) of \(doc)
        end tell
        """)
        guard PowerPointController.hasAccessibility, let app = AX.app(bundleID) else {
            // Without Accessibility: Keynote's normal full-screen show, on the display set in Keynote's settings.
            try await runner.run("\(tellKeynote)\nstart \(doc) from slide \(slide) of \(doc)\nend tell")
            usingWindowedShow = false
            return false
        }
        let before = Set(AX.windows(app).map { CFHash($0) })
        try await runner.run("\(tellKeynote) to activate")
        try await Task.sleep(nanoseconds: 300_000_000)
        guard AX.pressMenu(app, ["Play", "Play Slideshow in Window"]) else {
            try await runner.run("\(tellKeynote)\nstart \(doc) from slide \(slide) of \(doc)\nend tell")
            usingWindowedShow = false
            return false
        }
        usingWindowedShow = true
        // Find the slideshow window Keynote just opened.
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 150_000_000)
            if let w = AX.windows(app).first(where: { !before.contains(CFHash($0)) }) { showWindow = w; break }
        }
        guard let window = showWindow else { return false }
        let target = fullScreen ? screen.frame
            : screen.visibleFrame.insetBy(dx: screen.visibleFrame.width * 0.2, dy: screen.visibleFrame.height * 0.2)
        AX.setFrame(of: window, to: AX.axFrame(target))
        guard fullScreen else { return true }
        try await Task.sleep(nanoseconds: 300_000_000)
        return AX.setFullScreen(window, true)
    }

    func next() async throws { try await runner.run("\(tellKeynote) to show next") }
    func previous() async throws { try await runner.run("\(tellKeynote) to show previous") }

    /// Keynote's slide switcher jumps straight to a slide during a show.
    func goTo(_ slide: Int) async throws {
        try await runner.run("""
        \(tellKeynote)
            set cur to slide number of current slide of \(doc)
            if cur = \(slide) then return
            show slide switcher
            if \(slide) > cur then
                repeat (\(slide) - cur) times
                    move slide switcher forward
                end repeat
            else
                repeat (cur - \(slide)) times
                    move slide switcher backward
                end repeat
            end if
            accept slide switcher
        end tell
        """)
    }

    /// Keynote can't black out the screen by script; Bema draws it on the audience overlay instead.
    func setScreen(_ state: PowerPointController.ScreenState) async throws {}

    func endShow() async throws {
        if let w = showWindow, AX.isFullScreen(w) {
            _ = AX.setFullScreen(w, false)
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
        try? await runner.run("\(tellKeynote)\nstop \(doc)\nend tell")
        showWindow = nil
    }

    func status() async throws -> ShowStatus {
        let out = try await runner.run("""
        \(tellKeynote)
            if not (exists \(doc)) then return "closed"
            if not playing then return "none"
            return (slide number of current slide of \(doc)) as text
        end tell
        """)
        switch out {
        case "closed": return .presentationClosed
        case "none", "": return .notRunning
        default:
            return .running(slide: Int(out) ?? 0, black: false, white: false, done: false, frame: showFrame())
        }
    }

    /// Where the slideshow is drawn, for the pointer overlay.
    private func showFrame() -> CGRect? {
        if let w = showWindow, let f = AX.frame(of: w) {
            var r = AX.cocoaFrame(f)
            if !AX.isFullScreen(w) {
                // Leave out the window's title bar.
                r.size.height -= 28
            }
            return r
        }
        // Keynote's own full-screen show: the largest on-screen Keynote window.
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        let rects = list.filter { ($0[kCGWindowOwnerName as String] as? String)?.contains("Keynote") == true }
            .compactMap { info -> CGRect? in
                guard let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { return nil }
                return CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            }
        return rects.max { $0.width * $0.height < $1.width * $1.height }.map(AX.cocoaFrame)
    }

    func activePresentationURL() async -> URL? {
        guard SlideshowApps.isRunning(bundleID) else { return nil }
        let path = try? await runner.run("""
        \(tellKeynote)
            if (count of documents) = 0 then return ""
            try
                return POSIX path of ((file of front document) as alias)
            end try
            return ""
        end tell
        """)
        guard let path, path.hasPrefix("/"), FileManager.default.fileExists(atPath: path),
              SlideshowApps.keynoteExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) else { return nil }
        return URL(fileURLWithPath: path)
    }
}
