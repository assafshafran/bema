import SwiftUI

/// Self view (only you) and the camera bubble on the slides (the audience), side by side.
struct CameraControls: View {
    @ObservedObject private var camera = CameraModel.shared

    var body: some View {
        HStack(spacing: 8) {
            Button { toggleSelfView() } label: {
                LabeledIcon(symbol: camera.selfViewOpen ? "person.crop.square.fill" : "person.crop.square",
                            label: "Self view", on: camera.selfViewOpen)
            }
            .buttonStyle(.plain)
            .help(camera.selfViewOpen ? "Close your self view" : "Show your camera in a small window only you see (hidden from screen sharing) (⌥⌘V)")
            Button { camera.enabled.toggle() } label: {
                LabeledIcon(symbol: camera.enabled ? "person.crop.circle.fill" : "person.crop.circle",
                            label: "On slides", on: camera.enabled)
            }
            .buttonStyle(.plain)
            .help(camera.enabled ? "Remove your camera from the slides" : "Show your camera in a bubble on the slides the audience sees")
            if camera.selfViewOpen || camera.enabled {
                Button { CameraModel.showVideoEffects() } label: {
                    LabeledIcon(symbol: "camera.filters", label: "Effects", on: false)
                }
                .buttonStyle(.plain)
                .help("macOS video effects for Bema's camera: turn Edge Light, Portrait or Studio Light on or off")
            }
        }
    }

    private func toggleSelfView() {
        SelfViewWindowRef.toggle()
    }
}

/// What the Self view button does: decided by whether the window is really on screen, not by a flag
/// that a missed close could leave wrong.
enum SelfViewToggle {
    enum Action: Equatable { case open, close }

    static func action(windowVisible: Bool) -> Action { windowVisible ? .close : .open }
}
