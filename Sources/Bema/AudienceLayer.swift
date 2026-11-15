import AVFoundation
import SwiftUI

/// Everything Bema draws over the slide on the audience display.
struct AudienceLayer: View {
    var body: some View {
        ZStack {
            AnnotationCanvas()
            CameraBubble()
            PollOverlay()
            CaptionsBar()
            ScreenBlank()
        }
    }
}

/// Black or white screen, drawn by Bema when the presentation app can't do it itself (Keynote).
struct ScreenBlank: View {
    @EnvironmentObject private var model: PresenterModel

    var body: some View {
        if !model.app.supportsScreenStates && model.audience != .normal {
            Rectangle().fill(model.audience == .black ? Color.black : Color.white)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Camera bubble

@MainActor
final class CameraModel: ObservableObject {
    static let shared = CameraModel()

    enum Corner: String, CaseIterable, Identifiable {
        case bottomRight, bottomLeft, topRight, topLeft
        var id: String { rawValue }
        var label: String {
            switch self {
            case .bottomRight: return "Bottom right"
            case .bottomLeft: return "Bottom left"
            case .topRight: return "Top right"
            case .topLeft: return "Top left"
            }
        }
        var alignment: Alignment {
            switch self {
            case .bottomRight: return .bottomTrailing
            case .bottomLeft: return .bottomLeading
            case .topRight: return .topTrailing
            case .topLeft: return .topLeading
            }
        }
    }

    /// The camera bubble on the audience slide.
    @Published var enabled = false { didSet { update() } }
    /// The self-view window (only you see it; hidden from screen sharing).
    @Published var selfViewOpen = false { didSet { update() } }
    @Published var selfViewRound: Bool = UserDefaults.standard.bool(forKey: "selfViewRound") {
        didSet { UserDefaults.standard.set(selfViewRound, forKey: "selfViewRound") }
    }
    @Published var corner: Corner = Corner(rawValue: UserDefaults.standard.string(forKey: "cameraCorner") ?? "") ?? .bottomRight {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: "cameraCorner") }
    }
    @Published var size: Double = UserDefaults.standard.object(forKey: "cameraSize") as? Double ?? 0.2 {
        didSet { UserDefaults.standard.set(size, forKey: "cameraSize") }
    }
    @Published private(set) var error: String?

    let session = AVCaptureSession()
    private var configured = false

    /// macOS's own video effects menu (Edge Light, Portrait, Studio Light, reactions). These effects
    /// belong to macOS and apply while Bema uses the camera; Bema can only open the menu.
    static func showVideoEffects() {
        AVCaptureDevice.showSystemUserInterface(.videoEffects)
    }

    /// The camera runs while the bubble or the self view needs it.
    private func update() {
        if enabled || selfViewOpen { start() } else { stop() }
    }

    private func start() {
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                error = "The camera needs access: System Settings → Privacy & Security → Camera."
                enabled = false
                return
            }
            if !configured {
                guard let device = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) else {
                    error = "No camera found."
                    enabled = false
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .high
                session.addInput(input)
                session.commitConfiguration()
                configured = true
            }
            error = nil
            let session = self.session
            DispatchQueue.global(qos: .userInitiated).async { if !session.isRunning { session.startRunning() } }
        }
    }

    private func stop() {
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { if session.isRunning { session.stopRunning() } }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// A round webcam view in a corner of the audience slide, for recorded or hybrid talks.
struct CameraBubble: View {
    @ObservedObject private var camera = CameraModel.shared

    var body: some View {
        GeometryReader { geo in
            if camera.enabled {
                let d = geo.size.width * camera.size
                CameraPreview(session: camera.session)
                    .frame(width: d, height: d)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white, lineWidth: max(3, d * 0.02)))
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                    .padding(geo.size.width * 0.025)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: camera.corner.alignment)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Poll on the audience screen

struct PollOverlay: View {
    @ObservedObject private var poll = PollModel.shared
    @ObservedObject private var server = RemoteServer.shared

    var body: some View {
        GeometryReader { geo in
            if poll.onScreen {
                let w = max(260, geo.size.width * 0.32)
                let scale = w / 320
                VStack(alignment: .leading, spacing: 12 * scale) {
                    Text(poll.question)
                        .font(.system(size: 20 * scale, weight: .bold))
                        .foregroundStyle(Color(hex: 0x14161B))
                        .fixedSize(horizontal: false, vertical: true)
                    if poll.showResults {
                        ForEach(Array(poll.options.enumerated()), id: \.offset) { i, option in
                            let count = poll.votes.indices.contains(i) ? poll.votes[i] : 0
                            let share = poll.totalVotes > 0 ? Double(count) / Double(poll.totalVotes) : 0
                            VStack(alignment: .leading, spacing: 4 * scale) {
                                HStack {
                                    Text(option).font(.system(size: 15 * scale, weight: .semibold))
                                    Spacer()
                                    Text("\(Int((share * 100).rounded()))%").font(.system(size: 14 * scale, weight: .bold)).monospacedDigit()
                                }
                                .foregroundStyle(Color(hex: 0x14161B))
                                GeometryReader { g in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(hex: 0xE6E8EC))
                                        Capsule().fill(Theme.accent).frame(width: g.size.width * share)
                                    }
                                }
                                .frame(height: 10 * scale)
                                .animation(.easeOut(duration: 0.4), value: share)
                            }
                        }
                    }
                    HStack(spacing: 12 * scale) {
                        if let url = server.pollURL, let qr = RemoteServer.qrCode(for: url.absoluteString) {
                            Image(nsImage: qr).interpolation(.none).resizable().frame(width: 92 * scale, height: 92 * scale)
                        }
                        VStack(alignment: .leading, spacing: 4 * scale) {
                            Text("Scan to vote").font(.system(size: 15 * scale, weight: .bold))
                            Text("\(poll.totalVotes) vote\(poll.totalVotes == 1 ? "" : "s")").font(.system(size: 13 * scale)).monospacedDigit()
                            Text("Same Wi-Fi as the presenter").font(.system(size: 11 * scale)).opacity(0.6)
                        }
                        .foregroundStyle(Color(hex: 0x14161B))
                    }
                }
                .padding(18 * scale)
                .frame(width: w, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16 * scale).fill(.white))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
                .padding(geo.size.width * 0.025)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .environment(\.layoutDirection, poll.question.isRightToLeft ? .rightToLeft : .leftToRight)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Self view

/// Your own camera in a small floating window that only you see: it's excluded from screen sharing,
/// recordings and screenshots, floats above the slideshow and your call app, and is mirrored.
struct SelfViewWindow: View {
    @ObservedObject private var camera = CameraModel.shared
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.black
            CameraPreview(session: camera.session)
            if let error = camera.error {
                Text(error).font(.system(size: 12)).foregroundStyle(.white).multilineTextAlignment(.center).padding(12)
            }
            // Drag anywhere to move; controls appear on hover.
            WindowDragArea()
            if hovering {
                VStack {
                    HStack(spacing: 6) {
                        Spacer()
                        SelfViewButton(symbol: camera.selfViewRound ? "rectangle" : "circle", help: camera.selfViewRound ? "Rectangle" : "Circle") {
                            camera.selfViewRound.toggle()
                        }
                        SelfViewButton(symbol: "web.camera", help: "Move under the camera") { SelfViewWindowRef.placeUnderCamera() }
                        SelfViewButton(symbol: "camera.filters", help: "Video effects: Edge Light, Portrait, Studio Light…") { CameraModel.showVideoEffects() }
                        SelfViewButton(symbol: "xmark", help: "Close the self view") { SelfViewWindowRef.window?.close() }
                    }
                    Spacer()
                    Label("Only you see this", systemImage: "eye.slash")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(.black.opacity(0.55)))
                        .foregroundStyle(.white)
                }
                .padding(8)
            }
        }
        .clipShape(camera.selfViewRound ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 14)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .background(SelfViewConfigurator())
        .frame(minWidth: 140, minHeight: 105)
        .ignoresSafeArea()
        .onAppear { camera.selfViewOpen = true }
        .onDisappear { camera.selfViewOpen = false }
    }
}

private struct SelfViewButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                .frame(width: 24, height: 24).background(Circle().fill(.black.opacity(0.55)))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

@MainActor
enum SelfViewWindowRef {
    static weak var window: NSWindow?

    static var isVisible: Bool { window?.isVisible ?? false }

    /// SwiftUI's window opener, kept from the first Bema view that appears, so the self view can
    /// open even after the main window was closed (from the menu bar, ⌥⌘V or a bema:// link).
    static var opener: OpenWindowAction?

    static func open() {
        if let opener { opener(id: "selfview") }
        else { NotificationCenter.default.post(name: .openSelfView, object: nil) }
    }

    static func closed() {
        window = nil
        CameraModel.shared.selfViewOpen = false
    }

    /// Top centre of the display with the built-in camera, just below the menu bar.
    static func placeUnderCamera() {
        guard let w = window else { return }
        let screen = NSScreen.screens.first { $0.localizedName.localizedCaseInsensitiveContains("built-in") } ?? NSScreen.main ?? w.screen
        guard let vf = screen?.visibleFrame else { return }
        let size = w.frame.size
        w.setFrame(NSRect(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 8, width: size.width, height: size.height),
                   display: true, animate: true)
    }
}

/// Borderless look, floating, on every Space, and never captured by screen sharing.
private struct SelfViewConfigurator: NSViewRepresentable {
    final class Probe: NSView {
        private var closeObserver: NSObjectProtocol?
        deinit { if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) } }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let w = window else { return }
            SelfViewWindowRef.window = w
            CameraModel.shared.selfViewOpen = true
            // SwiftUI's onDisappear doesn't always run when a Window scene closes; without this the
            // camera kept running and Bema thought the self view was still open.
            if closeObserver == nil {
                closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                    MainActor.assumeIsolated { SelfViewWindowRef.closed() }
                }
            }
            w.sharingType = .none
            w.level = .floating
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.styleMask.insert(.fullSizeContentView)
            w.standardWindowButton(.closeButton)?.isHidden = true
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.isOpaque = false
            w.backgroundColor = .clear
            w.hasShadow = true
            w.hidesOnDeactivate = false
            w.isMovableByWindowBackground = true
            w.aspectRatio = NSSize(width: 4, height: 3)
        }
    }
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
