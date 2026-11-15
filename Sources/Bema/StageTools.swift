import SwiftUI

/// The "Stage tools" popover: phone remote, live poll, camera bubble, captions, voice commands, coach.
struct StageToolsButton: View {
    @EnvironmentObject private var model: PresenterModel
    @ObservedObject private var server = RemoteServer.shared
    @ObservedObject private var poll = PollModel.shared
    @ObservedObject private var camera = CameraModel.shared

    var body: some View {
        Button { model.stageToolsOpen.toggle() } label: {
            LabeledIcon(symbol: "slider.horizontal.3", label: "Stage tools",
                        on: server.remoteEnabled || poll.onScreen || camera.enabled || model.alwaysOnTop)
        }
        .buttonStyle(.plain)
        .help("Stage tools (⇧⌘T): phone remote, live poll, camera bubble, captions, voice commands, rehearsal")
        .popover(isPresented: $model.stageToolsOpen, arrowEdge: .bottom) {
            StageToolsPanel().preferredColorScheme(Theme.colorScheme)
        }
    }
}

struct StageToolsPanel: View {
    @ObservedObject private var server = RemoteServer.shared
    @ObservedObject private var poll = PollModel.shared
    @ObservedObject private var camera = CameraModel.shared
    @ObservedObject private var coach = CoachModel.shared
    @ObservedObject private var voice = VoiceCommands.shared
    @ObservedObject private var captions = Captions.shared
    @ObservedObject private var presenter = PresenterModel.shared
    @AppStorage("hidePresenterFromSharing") private var hidePresenterFromSharing = false
    @State private var optionsText = PollModel.shared.options.joined(separator: "\n")

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                section("Phone remote") {
                    Toggle("Control the show from your phone", isOn: $server.remoteEnabled)
                    if server.remoteEnabled {
                        if let url = server.remoteURL, let qr = RemoteServer.qrCode(for: url.absoluteString) {
                            HStack(alignment: .top, spacing: 14) {
                                Image(nsImage: qr).interpolation(.none).resizable().frame(width: 132, height: 132)
                                    .padding(6).background(RoundedRectangle(cornerRadius: 8).fill(.white))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Scan with your phone's camera.").font(.system(size: 13, weight: .medium))
                                    Text("Your phone and this Mac need to be on the same Wi-Fi. The link has a secret code, so only you can use it.")
                                        .font(.system(size: 12)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                                    Text(url.absoluteString).font(.system(size: 11)).foregroundStyle(Theme.dim).textSelection(.enabled)
                                }
                            }
                        } else if let error = server.error {
                            Text(error).font(.system(size: 12)).foregroundStyle(Theme.warnStrong)
                        } else {
                            Text("Starting… If macOS asks to allow incoming connections, choose Allow.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        }
                    }
                }

                section("Live poll") {
                    TextField("Question", text: $poll.question).textFieldStyle(.roundedBorder)
                    Text("Answers, one per line (up to 6)").font(.system(size: 12)).foregroundStyle(Theme.muted)
                    TextEditor(text: $optionsText)
                        .font(.system(size: 13))
                        .frame(height: 74)
                        .scrollContentBackground(.hidden)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.ground))
                        .onChange(of: optionsText) {
                            let opts = optionsText.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                            if opts != poll.options { poll.setOptions(Array(opts.prefix(6))) }
                        }
                    HStack {
                        Toggle("Show on the audience screen", isOn: $poll.onScreen)
                        Spacer()
                        Toggle("Results", isOn: $poll.showResults).toggleStyle(.checkbox)
                    }
                    HStack {
                        Text("\(poll.totalVotes) vote\(poll.totalVotes == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(Theme.muted)
                        Spacer()
                        Button("Reset votes") { poll.reset() }.disabled(poll.totalVotes == 0)
                    }
                }

                section("Camera bubble") {
                    Toggle("Show my camera on the slides", isOn: $camera.enabled)
                    if camera.enabled {
                        Picker("Corner", selection: $camera.corner) {
                            ForEach(CameraModel.Corner.allCases) { Text($0.label).tag($0) }
                        }
                        Slider(value: $camera.size, in: 0.12...0.35) { Text("Size") }
                    }
                    if let error = camera.error { Text(error).font(.system(size: 12)).foregroundStyle(Theme.warnStrong) }
                }

                section("Listening") {
                    Toggle("Live captions on the audience screen", isOn: $captions.enabled)
                    Toggle("Voice commands (“next slide”, “go to slide 5”, “go to pricing”)", isOn: $voice.enabled)
                    Toggle("Speech coach (speaking speed, filler words)", isOn: $coach.listen)
                    Text("Listening starts when the show starts, using on-device recognition when your language supports it.")
                        .font(.system(size: 11)).foregroundStyle(Theme.dim).fixedSize(horizontal: false, vertical: true)
                }

                section("Presenter window") {
                    Toggle("Keep on top of other windows", isOn: $presenter.alwaysOnTop)
                    Toggle("Hide from screen sharing", isOn: $hidePresenterFromSharing)
                }

                section("Rehearsal") {
                    Toggle("Rehearsal mode: report when the show ends", isOn: $coach.rehearsalMode)
                    Toggle("Cue a minute before time is up", isOn: $coach.timeCue)
                }
            }
            .padding(18)
        }
        .frame(width: 400, height: 560)
        .background(Theme.panel)
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    @ViewBuilder private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(title)
            content()
        }
        .font(.system(size: 13))
    }
}
