import AppKit
import SwiftUI

// MARK: - Layout helpers

/// Wraps words into lines, left-to-right or right-to-left.
struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    var rtl = false

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(for: subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: width.isFinite ? width : used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = rtl ? bounds.maxX : bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                if rtl {
                    subviews[i].place(at: CGPoint(x: x - size.width, y: y), anchor: .topLeading, proposal: .unspecified)
                    x -= size.width + spacing
                } else {
                    subviews[i].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
                    x += size.width + spacing
                }
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            let needed = rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(i)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// The top of every word, in the script's own coordinates.
struct WordTopsKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Maps a (fractional) reading position to a vertical offset and back, moving smoothly through each line.
struct ScriptGeometry {
    private struct Line { let top: CGFloat; let first: Int; let count: Int }
    private var lines: [Line] = []
    private var lineOfWord: [Int] = []
    private let lineHeight: CGFloat

    init(tops: [Int: CGFloat], count: Int, lineHeight: CGFloat) {
        self.lineHeight = lineHeight
        guard count > 0, !tops.isEmpty else { return }
        var current: (top: CGFloat, first: Int, count: Int)?
        var lastTop: CGFloat = 0
        for i in 0..<count {
            let top = tops[i] ?? lastTop
            lastTop = top
            if let c = current, abs(c.top - top) < 1 {
                current = (c.top, c.first, c.count + 1)
            } else {
                if let c = current { lines.append(Line(top: c.top, first: c.first, count: c.count)) }
                current = (top, i, 1)
            }
            lineOfWord.append(lines.count)
        }
        if let c = current { lines.append(Line(top: c.top, first: c.first, count: c.count)) }
    }

    func y(for position: Double) -> CGFloat {
        guard !lines.isEmpty else { return 0 }
        if position >= Double(lineOfWord.count) { return lines[lines.count - 1].top + lineHeight }
        let i = max(0, Int(position))
        let f = position - Double(i)
        let li = lineOfWord[i]
        let line = lines[li]
        let next = li + 1 < lines.count ? lines[li + 1].top : line.top + lineHeight
        let frac = (Double(i - line.first) + f) / Double(line.count)
        return line.top + CGFloat(frac) * (next - line.top)
    }

    func position(for y: CGFloat) -> Double {
        guard let firstLine = lines.first else { return 0 }
        if y <= firstLine.top { return 0 }
        for (li, line) in lines.enumerated() {
            let next = li + 1 < lines.count ? lines[li + 1].top : line.top + lineHeight
            if y < next {
                let frac = Double((y - line.top) / max(next - line.top, 1))
                return Double(line.first) + frac * Double(line.count)
            }
        }
        return Double(lineOfWord.count)
    }
}

// MARK: - Prompter view

struct PrompterView: View {
    @ObservedObject private var prompter = PrompterModel.shared
    @ObservedObject private var hub = SpeechHub.shared
    @EnvironmentObject private var model: PresenterModel
    @Environment(\.openWindow) private var openWindow
    let compact: Bool
    @AppStorage private var fontSize: Double
    @State private var wordTops: [Int: CGFloat] = [:]
    @State private var dragStart: CGFloat?
    @State private var lastWheel = Date.distantPast
    // Detached window options
    @AppStorage("prompterFloat") private var floatOnTop = true
    @AppStorage("prompterHideFromSharing") private var hideFromSharing = true
    @AppStorage("prompterControlsCollapsed") private var collapsed = false
    @AppStorage("prompterReadingLine") private var readingLine = 0.16

    private var detached: Bool { !compact }

    init(compact: Bool) {
        self.compact = compact
        _fontSize = AppStorage(wrappedValue: compact ? 28 : 44, compact ? "prompterFont" : "prompterWindowFont")
    }

    var body: some View {
        VStack(spacing: 0) {
            if detached && collapsed {
                collapsedBar
            } else {
                controls
                Rectangle().fill(Theme.border).frame(height: 1)
            }
            scriptArea
        }
    }

    /// A thin bar for the detached window: drag to move, show the controls again.
    private var collapsedBar: some View {
        HStack(spacing: 10) {
            Spacer()
            Button { prompter.toggle() } label: { Image(systemName: prompter.running ? "pause.fill" : "play.fill") }
                .buttonStyle(.plain).foregroundStyle(Theme.accent)
                .help(prompter.running ? "Pause" : "Start")
            if hideFromSharing {
                Image(systemName: "eye.slash").font(.system(size: 11)).foregroundStyle(Theme.dim)
                    .help("Hidden from screen sharing")
            }
            Button { collapsed = false } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.plain).foregroundStyle(Theme.muted)
                .help("Show the controls")
        }
        .font(.system(size: 12, weight: .semibold))
        .padding(.leading, 76).padding(.trailing, 12)
        .frame(height: 28)
        .background(WindowDragArea())
        .background(Theme.bar)
    }

    /// Window options shown only in the detached prompter.
    @ViewBuilder private var windowOptions: some View {
        Button { floatOnTop.toggle() } label: { LabeledIcon(symbol: floatOnTop ? "pin.fill" : "pin", label: "On top", on: floatOnTop) }
            .buttonStyle(.plain)
            .help(floatOnTop ? "Floating above other windows" : "Float above other windows")
        Button { hideFromSharing.toggle() } label: { LabeledIcon(symbol: hideFromSharing ? "eye.slash" : "eye", label: hideFromSharing ? "Hidden" : "Shared", on: hideFromSharing) }
            .buttonStyle(.plain)
            .help(hideFromSharing ? "Hidden from screen sharing and screenshots" : "Visible in screen sharing")
        Button { PrompterWindowRef.placeUnderCamera() } label: { LabeledIcon(symbol: "web.camera", label: "Camera", on: false) }
            .buttonStyle(.plain)
            .help("Move this window to the top of the screen, just under the camera")
        Button { collapsed = true } label: { LabeledIcon(symbol: "chevron.up", label: "Hide", on: false) }
            .buttonStyle(.plain)
            .help("Hide the controls")
    }

    // MARK: Controls

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button { prompter.toggle() } label: {
                    Label(prompter.running ? "Pause" : "Start", systemImage: prompter.running ? "pause.fill" : "play.fill").fixedSize()
                }
                .buttonStyle(PillButtonStyle(kind: prompter.running ? .normal : .accent, height: 32))
                .help(prompter.running ? "Pause the prompter" : "Start the prompter")

                SegmentGroup {
                    ForEach(PrompterModel.Mode.allCases) { m in
                        Button(m.label) { prompter.mode = m }
                            .buttonStyle(SegmentButtonStyle(isOn: prompter.mode == m, width: nil, height: 26))
                    }
                }
                .help("Voice follows what you say · Auto scrolls at a set speed · Manual: drag or click a word")

                Spacer(minLength: 4)

                if compact {
                    Button { openWindow(id: "prompter") } label: { LabeledIcon(symbol: "arrow.up.forward.app", label: "Detach", on: false) }
                        .buttonStyle(.plain)
                        .help("Detach the prompter: a floating window you can put under your camera, hidden from screen sharing")
                } else {
                    windowOptions
                }
            }
            .padding(.leading, detached ? 62 : 0)

            HStack(spacing: 10) {
                switch prompter.mode {
                case .voice:
                    MicrophoneMenu()
                    Menu {
                        ForEach(PrompterModel.Language.allCases) { lang in
                            Button { prompter.language = lang } label: {
                                if lang == prompter.language { Label(lang.label, systemImage: "checkmark") } else { Text(lang.label) }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(prompter.language.label)
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                        }
                        .font(.system(size: 12)).foregroundStyle(Theme.textSoft)
                    }
                    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                case .auto:
                    Text("\(Int(prompter.wordsPerMinute)) wpm").font(Theme.numeral(12, .medium)).foregroundStyle(Theme.textSoft)
                        .frame(width: 62, alignment: .leading)
                    Slider(value: $prompter.wordsPerMinute, in: 60...240, step: 5).frame(maxWidth: 160)
                case .manual:
                    EmptyView()
                }

                Spacer(minLength: 4)

                Button { prompter.followSlides.toggle() } label: {
                    LabeledIcon(symbol: "rectangle.stack", label: "Follow", on: prompter.followSlides)
                }
                .buttonStyle(.plain)
                .help(prompter.followSlides
                      ? "Follow slides is on: the slideshow moves on when the script reaches the next slide, and the script jumps when you change slides"
                      : "Follow slides is off: the script and the slideshow move separately")
                Menu {
                    Picker("Reading line", selection: $readingLine) {
                        Text("Top (see the most ahead)").tag(0.16)
                        Text("Upper third").tag(0.3)
                        Text("Middle").tag(0.45)
                    }
                    .pickerStyle(.inline)
                } label: {
                    LabeledIcon(symbol: "text.line.first.and.arrowtriangle.forward", label: "Line", on: false)
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .help("Reading line: where the line you're reading sits. Higher shows more of what's coming")
                Button { prompter.mirrored.toggle() } label: {
                    LabeledIcon(symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right", label: "Mirror", on: prompter.mirrored)
                }
                .buttonStyle(.plain)
                .help("Mirror the text left-to-right, for teleprompter glass")
                Button { fontSize = max(fontSize - 4, 18) } label: { LabeledIcon(symbol: "textformat.size.smaller", label: "Smaller", on: false) }
                    .buttonStyle(.plain)
                    .help("Smaller text")
                Button { fontSize = min(fontSize + 4, 120) } label: { LabeledIcon(symbol: "textformat.size.larger", label: "Bigger", on: false) }
                    .buttonStyle(.plain)
                    .help("Bigger text")
            }

            if let status = prompter.status ?? (prompter.mode == .voice && prompter.running ? hub.status : nil) {
                Text(status).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(2)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(detached ? AnyView(WindowDragArea()) : AnyView(Color.clear))
    }

    // MARK: Script

    private var scriptArea: some View {
        GeometryReader { geo in
            let readingY = max(fontSize * 0.6, geo.size.height * readingLine)
            let geometry = ScriptGeometry(tops: wordTops, count: prompter.words.count, lineHeight: fontSize * 1.4)
            let offset = readingY - geometry.y(for: prompter.position)
            let hpad = max(24, geo.size.width * 0.06)

            ZStack(alignment: .topLeading) {
                if prompter.words.isEmpty {
                    Text("This deck has no speaker notes yet. Add notes in PowerPoint and they become your script.")
                        .font(.system(size: 15)).foregroundStyle(Theme.muted)
                        .padding(24)
                } else {
                    ScriptBody(paragraphs: prompter.paragraphs, current: prompter.currentWordIndex, fontSize: fontSize) { id in
                        prompter.jump(to: id)
                    }
                    .equatable()
                    .frame(width: max(geo.size.width - hpad * 2, 100), alignment: .topLeading)
                    .coordinateSpace(name: "script")
                    .onPreferenceChange(WordTopsKey.self) { wordTops = $0 }
                    .padding(.horizontal, hpad)
                    .offset(y: offset)
                    // While running, the model already moves smoothly every frame; animate only clicks and slide jumps.
                    .animation(prompter.running || dragStart != nil || Date().timeIntervalSince(lastWheel) < 0.4
                               ? nil : .easeOut(duration: 0.3), value: offset)

                    // Reading line
                    Rectangle().fill(Theme.accent.opacity(0.07))
                        .frame(height: fontSize * 1.45)
                        .offset(y: readingY - fontSize * 0.2)
                        .allowsHitTesting(false)
                    Image(systemName: "arrowtriangle.right.fill")
                        .font(.system(size: max(12, fontSize * 0.35)))
                        .foregroundStyle(Theme.accent)
                        .offset(x: 6, y: readingY + fontSize * 0.25)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .clipped()
            .mask(
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .black, location: max(0.02, readingLine - 0.06)),
                                       .init(color: .black, location: 0.9), .init(color: .clear, location: 1)],
                               startPoint: .top, endPoint: .bottom)
            )
            .scaleEffect(x: prompter.mirrored ? -1 : 1, y: 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        if dragStart == nil { dragStart = geometry.y(for: prompter.position) }
                        prompter.setPosition(geometry.position(for: dragStart! - value.translation.height))
                    }
                    .onEnded { _ in dragStart = nil }
            )
            // Mouse wheel / trackpad scrolling, in every mode. Voice and Auto carry on from where you scroll to.
            .background(ScrollWheelReader { dy in
                lastWheel = Date()
                prompter.setPosition(geometry.position(for: geometry.y(for: prompter.position) - dy))
            })
        }
        .background(Theme.panel)
    }
}

/// A small icon with a one-word label under it, so less obvious controls explain themselves.
/// Set by a bar too narrow for captions: its labeled icons show the icon only (the tooltip stays).
private struct IconsOnlyKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var iconsOnly: Bool {
        get { self[IconsOnlyKey.self] }
        set { self[IconsOnlyKey.self] = newValue }
    }
}

struct LabeledIcon: View {
    let symbol: String
    let label: String
    let on: Bool
    @Environment(\.iconsOnly) private var iconsOnly
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: iconsOnly ? 15 : 13, weight: .medium)).frame(height: 16)
            if !iconsOnly {
                Text(label).font(.system(size: 9, weight: .semibold)).lineLimit(1).fixedSize()
            }
        }
        .accessibilityLabel(label)
        .foregroundStyle(on ? Theme.accent : (hovering ? Theme.text : Theme.muted))
        .frame(minWidth: iconsOnly ? 28 : 34, minHeight: 32)
        .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? Theme.raised : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// Reports scroll-wheel and trackpad scrolling over this view (content moves by `dy` points),
/// without getting in the way of clicks and drags.
struct ScrollWheelReader: NSViewRepresentable {
    var onScroll: (CGFloat) -> Void

    final class ReaderView: NSView {
        var onScroll: ((CGFloat) -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let p = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(p) else { return event }
                // Precise (trackpad) deltas are in points; a mouse wheel reports lines.
                let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 14
                if dy != 0 { self.onScroll?(dy) }
                return nil
            }
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }   // let clicks through
    }

    func makeNSView(context: Context) -> ReaderView {
        let v = ReaderView()
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ nsView: ReaderView, context: Context) { nsView.onScroll = onScroll }
}

/// The words of the script. Re-renders only when the current word, the size or the script changes.
struct ScriptBody: View, Equatable {
    let paragraphs: [ScriptParagraph]
    let current: Int
    let fontSize: Double
    let onTap: (Int) -> Void

    static func == (a: ScriptBody, b: ScriptBody) -> Bool {
        a.current == b.current && a.fontSize == b.fontSize && a.paragraphs.count == b.paragraphs.count
            && a.paragraphs.first?.words.first?.id == b.paragraphs.first?.words.first?.id
            && a.paragraphs.last?.words.last?.id == b.paragraphs.last?.words.last?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: fontSize * 0.6) {
            ForEach(paragraphs) { p in
                VStack(alignment: p.rtl ? .trailing : .leading, spacing: fontSize * 0.3) {
                    if p.isSlideStart {
                        CapsLabel("Slide \(p.slide)" + (p.slideTitle.isEmpty ? "" : " · \(p.slideTitle)"), color: Theme.dim)
                            .padding(.top, fontSize * 0.4)
                    }
                    FlowLayout(spacing: fontSize * 0.27, lineSpacing: fontSize * 0.3, rtl: p.rtl) {
                        ForEach(p.words) { w in
                            Group {
                                if w.isPlaceholder {
                                    Text(w.text)
                                        .font(.system(size: fontSize * 0.5, weight: .regular).italic())
                                        .foregroundStyle(Theme.dim)
                                } else if w.isCue {
                                    Text(w.text)
                                        .font(.system(size: fontSize * 0.42, weight: .heavy))
                                        .tracking(1)
                                        .foregroundStyle(Theme.accent)
                                        .padding(.horizontal, fontSize * 0.25).padding(.vertical, fontSize * 0.08)
                                        .background(Capsule().fill(Theme.accent.opacity(0.16)))
                                        .padding(.top, fontSize * 0.28)
                                } else {
                                    Text(w.text)
                                        .font(.system(size: fontSize, weight: w.bold ? .heavy : .medium))
                                        .foregroundStyle(w.id < current ? Theme.dim.opacity(0.6) : (w.id == current ? Theme.accent : Theme.textBright))
                                }
                            }
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: WordTopsKey.self, value: [w.id: g.frame(in: .named("script")).minY])
                                })
                                .onTapGesture { onTap(w.id) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: p.rtl ? .trailing : .leading)
            }
            Color.clear.frame(height: 2000)
        }
    }
}

/// The level meter, which is also the microphone picker: click it to choose which microphone the
/// prompter (and everything else that listens) uses.
struct MicrophoneMenu: View {
    @ObservedObject private var hub = SpeechHub.shared
    @State private var microphones: [DeviceChoice.Device] = []

    var body: some View {
        Menu {
            Section("Microphone") {
                Button { hub.microphoneID = nil } label: {
                    let name = "System default" + (CaptureDevices.defaultMicrophoneName.map { " (\($0))" } ?? "")
                    if DeviceChoice.resolve(saved: hub.microphoneID, available: microphones) == nil { Label(name, systemImage: "checkmark") } else { Text(name) }
                }
                ForEach(microphones) { mic in
                    Button { hub.microphoneID = mic.id } label: {
                        if DeviceChoice.resolve(saved: hub.microphoneID, available: microphones) == mic.id { Label(mic.name, systemImage: "checkmark") } else { Text(mic.name) }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                MicLevel(level: hub.listening ? hub.level : 0)
                Image(systemName: "mic").font(.system(size: 11)).foregroundStyle(Theme.textSoft)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(Theme.textSoft)
            }
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .onHover { if $0 { microphones = CaptureDevices.microphones() } }
        .onAppear { microphones = CaptureDevices.microphones() }
        .help("Microphone: \(hub.microphoneName ?? DeviceChoice.label(saved: hub.microphoneID, available: microphones, defaultName: CaptureDevices.defaultMicrophoneName)). Click to choose another")
    }
}

struct MicLevel: View {
    let level: Float
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { i in
                Capsule()
                    .fill(Float(i) / 5 < level ? Theme.ok : Theme.borderStrong)
                    .frame(width: 3, height: CGFloat(6 + i * 3))
            }
        }
        .frame(height: 18, alignment: .bottom)
        .accessibilityLabel("Microphone level")
    }
}

/// The detached prompter: a floating window you can put under the camera (or on any display, full screen,
/// mirrored for teleprompter glass), kept out of screen sharing.
struct PrompterWindow: View {
    @AppStorage("prompterFloat") private var floatOnTop = true
    @AppStorage("prompterHideFromSharing") private var hideFromSharing = true

    var body: some View {
        PrompterView(compact: false)
            .environmentObject(PresenterModel.shared)
            .background(Theme.panel.ignoresSafeArea())
            .preferredColorScheme(Theme.colorScheme)
            .tint(Theme.accent)
            .background(PrompterWindowConfigurator(floatOnTop: floatOnTop, hideFromSharing: hideFromSharing))
            .frame(minWidth: 420, minHeight: 160)
    }
}

/// Lets the user move a title-bar-less window by dragging this area.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
enum PrompterWindowRef {
    static weak var window: NSWindow?

    /// Top centre of the display with the built-in camera (or the main display), just below the menu bar.
    static func placeUnderCamera() {
        guard let w = window else { return }
        let screen = NSScreen.screens.first { $0.localizedName.localizedCaseInsensitiveContains("built-in") }
            ?? NSScreen.main ?? w.screen
        guard let vf = screen?.visibleFrame else { return }
        let width = min(860, vf.width * 0.56)
        let height = min(300, vf.height * 0.3)
        w.setFrame(NSRect(x: vf.midX - width / 2, y: vf.maxY - height, width: width, height: height), display: true, animate: true)
    }
}

struct PrompterWindowConfigurator: NSViewRepresentable {
    let floatOnTop: Bool
    let hideFromSharing: Bool

    final class Probe: NSView {
        var apply: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let w = window { apply?(w) }
        }
    }

    func makeNSView(context: Context) -> NSView {
        let probe = Probe()
        let configure = self.configure
        probe.apply = { configure($0) }
        return probe
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let w = nsView.window { configure(w) }
    }

    private func configure(_ w: NSWindow) {
        PrompterWindowRef.window = w
        w.titlebarAppearsTransparent = true
        w.titlebarSeparatorStyle = .none
        w.backgroundColor = Theme.nsBar
        w.appearance = NSAppearance(named: Theme.palette.isDark ? .darkAqua : .aqua)
        w.level = floatOnTop ? .floating : .normal
        w.collectionBehavior = floatOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenPrimary]
        w.hidesOnDeactivate = false
        // Excluded from screen sharing, screen recording and screenshots by other apps.
        w.sharingType = hideFromSharing ? .none : .readOnly
    }
}
