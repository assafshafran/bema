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
        }
    }

    private func toggleSelfView() {
        if camera.selfViewOpen { SelfViewWindowRef.window?.close() }
        else { NotificationCenter.default.post(name: .openSelfView, object: nil) }
    }
}
