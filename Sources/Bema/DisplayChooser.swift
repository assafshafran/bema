import AppKit
import SwiftUI

/// Which display the audience sees. Pure, so the choice can be tested without real displays.
enum AudienceDisplay {
    /// The saved display if it's connected; otherwise a display other than the one showing Bema's window;
    /// otherwise the first.
    static func choose(saved: String, displays: [String], presenter: String?) -> String? {
        if displays.contains(saved) { return saved }
        return displays.first { $0 != presenter } ?? displays.first
    }

    /// Ask before the show only when there's a real choice and the person hasn't turned asking off.
    static func shouldAsk(enabled: Bool, displayCount: Int) -> Bool {
        enabled && displayCount > 1
    }
}

/// A display as the chooser shows it.
struct DisplayOption: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let width: Int
    let height: Int
    let builtIn: Bool
    /// Bema's own window is on this display.
    let hasBema: Bool

    @MainActor static func current(presenter: NSScreen?) -> [DisplayOption] {
        NSScreen.screens.map { screen in
            let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
            return DisplayOption(name: screen.localizedName,
                                 width: Int(screen.frame.width), height: Int(screen.frame.height),
                                 builtIn: CGDisplayIsBuiltin(number) != 0,
                                 hasBema: screen == presenter)
        }
    }
}

/// Asked when the presenter starts the show with more than one display connected: where the slides go.
/// The usual display is already selected, so Return starts the show.
struct DisplayChooser: View {
    let options: [DisplayOption]
    @Binding var selection: String
    @Binding var askEachTime: Bool
    let start: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Where should the slides go?").font(.system(size: 20, weight: .semibold))
                Text("The audience sees the slideshow on this display. Your notes and the timer stay with Bema.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                ForEach(options) { option in
                    DisplayCard(option: option, selected: option.name == selection)
                        .onTapGesture(count: 2) { selection = option.name; start() }
                        .onTapGesture { selection = option.name }
                }
            }

            if options.first(where: { $0.name == selection })?.hasBema == true {
                Label("Bema is on this display too, so the slideshow opens in a window here. Pick another display for full screen.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12)).foregroundStyle(Theme.warnText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Toggle("Ask every time", isOn: $askEachTime)
                    .toggleStyle(.checkbox).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .help("Turn off to start on this display straight away. Change it later from “Slides on” in the top bar.")
                Spacer()
                Button("Cancel", action: cancel)
                    .buttonStyle(PillButtonStyle(kind: .normal, height: 34))
                    .keyboardShortcut(.cancelAction)
                Button(action: start) {
                    Label("Start slideshow", systemImage: "play.fill").fixedSize()
                }
                .buttonStyle(PillButtonStyle(kind: .accent, height: 34))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: max(480, CGFloat(options.count) * 202 + 48))
        .background(Theme.panel)
        .foregroundStyle(Theme.text)
    }
}

private struct DisplayCard: View {
    let option: DisplayOption
    let selected: Bool

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                // The display's shape, so a projector (4:3) and a TV (16:9) look different.
                let ratio = option.height > 0 ? CGFloat(option.width) / CGFloat(option.height) : 16 / 9
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Theme.accent.opacity(0.22) : Theme.raised)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Theme.accent : Theme.borderStrong, lineWidth: selected ? 2 : 1))
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: 128, maxHeight: 76)
                Image(systemName: option.builtIn ? "laptopcomputer" : "display")
                    .font(.system(size: 22)).foregroundStyle(selected ? Theme.accent : Theme.muted)
            }
            .frame(height: 80)
            VStack(spacing: 4) {
                Text(option.name).font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(verbatim: "\(option.width) × \(option.height)")
                    .font(.system(size: 11)).foregroundStyle(Theme.muted).lineLimit(1)
                Text(option.hasBema ? "Bema is here" : " ")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(option.hasBema ? Theme.raised : .clear))
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(12)
        .frame(width: 190)
        .background(RoundedRectangle(cornerRadius: 12).fill(selected ? Theme.selected : Theme.ground))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 2 : 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityLabel(option.hasBema ? "\(option.name), Bema is here" : option.name)
    }
}

/// The chooser as a sheet on the presenter window, starting on the usual display.
struct DisplayChooserSheet: View {
    @EnvironmentObject private var model: PresenterModel
    @State private var selection = ""
    @State private var options: [DisplayOption] = []

    var body: some View {
        DisplayChooser(options: options, selection: $selection, askEachTime: $model.askForDisplay,
                       start: {
                           model.audienceScreenName = selection
                           model.startShow()
                       },
                       cancel: { model.displayChooserOpen = false })
            .onAppear {
                options = DisplayOption.current(presenter: model.presenterWindow?.screen)
                selection = model.audienceScreen().localizedName
            }
    }
}
