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

    @Published var enabled = false { didSet { update() } }
    @Published var corner: Corner = Corner(rawValue: UserDefaults.standard.string(forKey: "cameraCorner") ?? "") ?? .bottomRight {
        didSet { UserDefaults.standard.set(corner.rawValue, forKey: "cameraCorner") }
    }
    @Published var size: Double = UserDefaults.standard.object(forKey: "cameraSize") as? Double ?? 0.2 {
        didSet { UserDefaults.standard.set(size, forKey: "cameraSize") }
    }
    @Published private(set) var error: String?

    let session = AVCaptureSession()
    private var configured = false

    private func update() {
        if enabled { start() } else { stop() }
    }

    private func start() {
        Task {
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                error = "The camera bubble needs camera access: System Settings → Privacy & Security → Camera."
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
