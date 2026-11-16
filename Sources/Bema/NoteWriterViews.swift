import AppKit
import SwiftUI

// MARK: - In the notes panel

/// The notes writer's menu in the notes panel header.
struct NoteWriterMenu: View {
    @EnvironmentObject private var model: PresenterModel

    var body: some View {
        Menu {
            Button("Write Notes for This Slide") { model.writeNotesForCurrentSlide() }
                .disabled(model.noteWriting != nil || model.currentSlide?.notes.isEmpty == false)
            Button("Write Notes for Slides Without Notes (\(model.slidesNeedingNotes.count))") { model.writeNotesForAllSlides() }
                .disabled(model.noteWriting != nil || model.slidesNeedingNotes.isEmpty)
            Divider()
            Button("Save \(model.drafts.count) Draft\(model.drafts.count == 1 ? "" : "s") to Deck") { model.saveDraftsToDeck() }
                .disabled(model.drafts.isEmpty)
            Button("Discard All Drafts") { model.discardAllDrafts() }
                .disabled(model.drafts.isEmpty)
            Divider()
            Button("Notes Writer Settings…") { model.noteWriterSettingsOpen = true }
        } label: {
            Image(systemName: "sparkles").font(.system(size: 14, weight: .semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(Theme.textSoft)
        .frame(width: 32, height: 32)
        .background(RoundedRectangle(cornerRadius: 9).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.borderStrong))
        .help("Write speaker notes for slides that have none")
        .accessibilityLabel("Notes writer")
    }
}

/// Shown for a slide with no notes: write some.
struct NoNotesView: View {
    @EnvironmentObject private var model: PresenterModel
    let slide: Int
    let fontSize: Double
    var type: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("No notes for this slide.")
                .font(.system(size: fontSize)).foregroundStyle(Theme.dim)
            if let w = model.noteWriting, w.slide == slide {
                WritingRow(progress: w)
            } else {
                HStack(spacing: 10) {
                    Button { model.writeNotesForCurrentSlide() } label: {
                        Label(writeLabel, systemImage: "sparkles").fixedSize()
                    }
                    .buttonStyle(PillButtonStyle(kind: .accent, height: 34))
                    .disabled(model.noteWriting != nil)
                    .help(writeHelp)
                    let missing = model.slidesNeedingNotes.count
                    if missing > 1 {
                        Button("All \(missing) slides without notes") { model.writeNotesForAllSlides() }
                            .buttonStyle(PillButtonStyle(kind: .normal, height: 34))
                            .disabled(model.noteWriting != nil)
                    }
                    Button { type() } label: { Label("Type notes", systemImage: "pencil").fixedSize() }
                        .buttonStyle(PillButtonStyle(kind: .normal, height: 34))
                        .help("Write this slide's notes yourself")
                }
            }
        }
    }

    private var writeLabel: String {
        NoteWriterSettings.load().kind == .claudeApp ? "Write notes in Claude" : "Write notes"
    }

    private var writeHelp: String {
        guard let kind = NoteWriterSettings.load().kind else { return "Choose who writes your notes, then write them" }
        return kind == .claudeApp
            ? "Copies the request and opens Claude; the notes come back here as a draft"
            : "\(kind.shortName) writes notes for this slide. They stay a draft in Bema until you save them to the deck."
    }
}

/// "Writing notes with Claude… slide 4 (2 of 9)" with Cancel.
struct WritingRow: View {
    @EnvironmentObject private var model: PresenterModel
    let progress: NoteWritingProgress

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(progress.total > 1
                 ? "Writing notes with \(progress.writer): slide \(progress.slide) (\(progress.done + 1) of \(progress.total))"
                 : "Writing notes with \(progress.writer)…")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            Button("Cancel") { model.cancelNoteWriting() }
                .buttonStyle(PillButtonStyle(kind: .normal, height: 28))
        }
    }
}

/// A draft's label and actions, above its text.
struct DraftBar: View {
    @EnvironmentObject private var model: PresenterModel
    let slide: Int
    @Binding var editing: Bool
    @Binding var text: String

    private var label: String {
        if editing { return "EDITING" }
        return model.draftReplacesDeckNotes(slide) ? "EDITED" : "DRAFT"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold)).tracking(0.8)
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Theme.accent.opacity(0.15)))
            Text(editing ? "Kept in Bema until you save it to the deck" : "Not in the deck yet")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer(minLength: 0)
            if editing {
                Button("Cancel") { editing = false }
                    .buttonStyle(PillButtonStyle(kind: .normal, height: 28))
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Done") { model.setDraft(text, for: slide); editing = false }
                    .buttonStyle(PillButtonStyle(kind: .accent, height: 28))
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Keep these notes (⌘↩)")
            } else {
                let edited = model.draftReplacesDeckNotes(slide)
                Button { text = model.drafts[slide] ?? ""; editing = true } label: { Image(systemName: "pencil") }
                    .buttonStyle(IconButtonStyle(tint: Theme.textSoft, size: 28)).help(edited ? "Edit your changes" : "Edit the draft")
                if !edited {
                    Button { model.writeNotes(for: [slide]) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(IconButtonStyle(tint: Theme.textSoft, size: 28)).help("Write it again")
                        .disabled(model.noteWriting != nil)
                }
                Button { model.discardDraft(for: slide) } label: { Image(systemName: edited ? "arrow.uturn.backward" : "trash") }
                    .buttonStyle(IconButtonStyle(tint: Theme.textSoft, size: 28))
                    .help(edited ? "Undo your changes and go back to the deck's notes" : "Discard the draft")
                Button { model.saveDraftsToDeck() } label: {
                    Label(model.drafts.count > 1 ? "Save \(model.drafts.count) to deck" : "Save to deck",
                          systemImage: "square.and.arrow.down").fixedSize()
                }
                .buttonStyle(PillButtonStyle(kind: .normal, height: 28))
                .help("Writes the draft notes into the deck's speaker notes in \(model.app.appName) and saves the deck")
            }
        }
    }
}

// MARK: - Settings

struct NoteWriterSettingsView: View {
    @EnvironmentObject private var model: PresenterModel
    @ObservedObject private var mcp = BemaMCP.shared
    @State private var settings = NoteWriterSettings.load()
    @State private var claudeKey = Keychain.read(.claude) ?? ""
    @State private var openAIKey = Keychain.read(.openAI) ?? ""
    @State private var localModels: [String] = []
    @State private var lookingForModels = false
    @State private var claudeConnected = ClaudeDesktop.isConnected
    @State private var connectError: String?
    @State private var copied = false
    @State private var findMessage: String?

    init(showing kind: NoteWriterKind? = nil) {
        var s = NoteWriterSettings.load()
        if let kind { s.kind = kind }
        _settings = State(initialValue: s)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Who writes your speaker notes?").font(.system(size: 20, weight: .semibold))
                Text("For slides that have no notes. What's written stays a draft in Bema, for you to edit, until you save it into the deck.")
                    .font(.system(size: 13)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 8) {
                ForEach(NoteWriterKind.allCases) { kind in
                    WriterRow(kind: kind, selected: settings.kind == kind) { settings.kind = kind }
                    if settings.kind == kind {
                        details(kind)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 34).padding(.trailing, 12).padding(.bottom, 6)
                    }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { model.noteWriterSettingsOpen = false }
                    .buttonStyle(PillButtonStyle(kind: .normal, height: 34))
                    .keyboardShortcut(.cancelAction)
                Button("Done") { save() }
                    .buttonStyle(PillButtonStyle(kind: .accent, height: 34))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560)
        .background(Theme.panel)
        .foregroundStyle(Theme.text)
        .onAppear { if settings.kind == nil { settings.kind = NoteWriter.onDeviceStatus.ready ? .onDevice : nil } }
    }

    private func save() {
        settings.save()
        Keychain.save(claudeKey, for: .claude)
        Keychain.save(openAIKey, for: .openAI)
        model.noteWriterSettingsOpen = false
    }

    @ViewBuilder private func details(_ kind: NoteWriterKind) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            switch kind {
            case .onDevice:
                let status = NoteWriter.onDeviceStatus
                note(status.ready ? "Ready. Reads the slide's text (not pictures)." : status.why, warn: !status.ready)
            case .local:
                field("Server", text: $settings.localURL, prompt: NoteWriterSettings.defaultLocalURL)
                HStack(spacing: 8) {
                    field("Model", text: $settings.localModel, prompt: "e.g. llama3.2")
                    if !localModels.isEmpty {
                        Menu("Choose") {
                            ForEach(localModels, id: \.self) { m in Button(m) { settings.localModel = m } }
                        }
                        .fixedSize()
                    }
                    Button(lookingForModels ? "Looking…" : "Find models") { findModels() }
                        .buttonStyle(PillButtonStyle(kind: .normal, height: 28))
                        .disabled(lookingForModels)
                }
                Toggle("Send the slide's picture too (for models that read images)", isOn: $settings.localSendsPicture)
                    .toggleStyle(.checkbox).font(.system(size: 12))
                if let m = findMessage { note(m, warn: true) }
                note("Ollama: http://localhost:11434/v1 · LM Studio: http://localhost:1234/v1")
            case .claude:
                secure("API key", text: $claudeKey, prompt: "sk-ant-…")
                field("Model", text: $settings.claudeModel, prompt: NoteWriterSettings.defaultClaudeModel)
                note("Billed to your Anthropic API account. Keys come from console.anthropic.com; Bema keeps yours in the Keychain.")
            case .openAI:
                secure("API key", text: $openAIKey, prompt: "sk-…")
                field("Model", text: $settings.openAIModel, prompt: NoteWriterSettings.defaultOpenAIModel)
                note("Billed to your OpenAI API account. Bema keeps your key in the Keychain.")
            case .claudeApp:
                claudeAppDetails
            }
        }
    }

    @ViewBuilder private var claudeAppDetails: some View {
        note("Claude can't be started from another app, so this works from Claude's side: Bema's button copies a request and opens Claude; you paste it, and Claude reads the slides from Bema and puts the notes back here as drafts. ChatGPT can't connect to apps on your Mac, so it isn't offered.")
        Toggle("Let Claude read and write notes", isOn: $mcp.enabled)
            .toggleStyle(.checkbox).font(.system(size: 12, weight: .medium))
        if let e = mcp.error { note(e, warn: true) }
        HStack(spacing: 8) {
            if claudeConnected {
                Label("Claude Desktop is connected", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.ok)
            } else {
                Button("Connect Claude Desktop") { connectClaude() }
                    .buttonStyle(PillButtonStyle(kind: .normal, height: 28))
                    .disabled(!ClaudeDesktop.isInstalled)
                if !ClaudeDesktop.isInstalled {
                    Text("Claude Desktop isn't installed.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
        }
        if claudeConnected { note("If Claude was open, quit it and open it again so it finds Bema.") }
        if let e = connectError { note(e, warn: true) }
        HStack(spacing: 8) {
            Text("Claude Code:").font(.system(size: 12)).foregroundStyle(Theme.muted)
            Text(verbatim: ClaudeDesktop.claudeCodeCommand)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textSoft)
                .lineLimit(1).truncationMode(.middle)
            Button(copied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(ClaudeDesktop.claudeCodeCommand, forType: .string)
                copied = true
            }
            .buttonStyle(PillButtonStyle(kind: .normal, height: 24))
        }
    }

    private func connectClaude() {
        do {
            try ClaudeDesktop.connect()
            mcp.enabled = true
            claudeConnected = ClaudeDesktop.isConnected
            connectError = nil
        } catch {
            connectError = error.localizedDescription
        }
    }

    private func findModels() {
        lookingForModels = true
        Task {
            let found = await NoteWriter.localModels(base: settings.localURL)
            localModels = found
            lookingForModels = false
            findMessage = found.isEmpty ? "No models found at that address. Is Ollama or LM Studio running?" : nil
            if !found.isEmpty, settings.localModel.isEmpty {
                settings.localModel = found[0]
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted).frame(width: 56, alignment: .leading)
            TextField(label, text: text, prompt: Text(prompt)).textFieldStyle(.roundedBorder).labelsHidden()
        }
    }

    private func secure(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted).frame(width: 56, alignment: .leading)
            SecureField(label, text: text, prompt: Text(prompt)).textFieldStyle(.roundedBorder).labelsHidden()
        }
    }

    private func note(_ text: String, warn: Bool = false) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(warn ? Theme.warnText : Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct WriterRow: View {
    let kind: NoteWriterKind
    let selected: Bool
    let choose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 15)).foregroundStyle(selected ? Theme.accent : Theme.muted)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).font(.system(size: 13, weight: .semibold))
                Text(kind.privacy).font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(selected ? Theme.selected : Theme.ground))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Theme.accent : Theme.border, lineWidth: selected ? 1.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: choose)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
