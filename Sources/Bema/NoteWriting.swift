import AppKit
import PDFKit

/// Writing notes now: which slide, and how far through a batch.
struct NoteWritingProgress: Equatable {
    var slide: Int
    var done: Int
    var total: Int
    var writer: String
}

/// Writing speaker notes for slides that have none, keeping them as drafts and saving them into the deck.
extension PresenterModel {
    /// Visible slides with no notes and no draft.
    var slidesNeedingNotes: [Int] { DraftNotes.needingNotes(slides) }
    var draftCount: Int { drafts.count }

    func writeNotesForCurrentSlide() { writeNotes(for: [current]) }
    func writeNotesForAllSlides() { writeNotes(for: slidesNeedingNotes) }

    func writeNotes(for ids: [Int]) {
        let settings = NoteWriterSettings.load()
        guard let kind = settings.kind else { noteWriterSettingsOpen = true; return }
        if kind == .claudeApp { askClaudeApp(for: ids); return }
        guard !ids.isEmpty, noteWriting == nil else { return }
        noteWritingTask = Task { [weak self] in
            guard let self else { return }
            var failed = 0
            var lastError: String?
            for (i, id) in ids.enumerated() {
                if Task.isCancelled { break }
                self.noteWriting = NoteWritingProgress(slide: id, done: i, total: ids.count, writer: kind.shortName)
                do {
                    let notes = try await NoteWriter.write(self.brief(for: id), settings: settings)
                    if Task.isCancelled { break }
                    self.setDraft(notes, for: id)
                } catch {
                    if Task.isCancelled { break }
                    failed += 1
                    lastError = error.localizedDescription
                    // A refusal or an empty answer is about one slide; anything else (no key, no server,
                    // no network) would fail for every slide, so stop.
                    if let e = error as? NoteWriterError, e == .refused || e == .empty { continue }
                    break
                }
            }
            self.noteWriting = nil
            self.noteWritingTask = nil
            if let lastError {
                self.notice = ids.count == 1 || failed == 1 ? lastError : "Notes for \(failed) slides weren't written. \(lastError)"
            }
        }
    }

    func cancelNoteWriting() {
        noteWritingTask?.cancel()
        noteWritingTask = nil
        noteWriting = nil
    }

    /// Stores the draft for a slide: notes written for it, or the presenter's edit. Text that matches the
    /// deck's notes (or empty text) removes the draft, so the deck's notes show again.
    func setDraft(_ text: String, for id: Int) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || DraftNotes.same(trimmed, deckNotes(for: id)) { drafts[id] = nil } else { drafts[id] = trimmed }
        notesChanged()
    }

    /// The slide's notes as the deck has them (not a draft).
    func deckNotes(for id: Int) -> String { deckSlides.first { $0.id == id }?.notes ?? "" }

    /// The slide has notes in the deck that a draft replaces.
    func draftReplacesDeckNotes(_ id: Int) -> Bool {
        drafts[id] != nil && !deckNotes(for: id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func discardDraft(for id: Int) { setDraft("", for: id) }

    func discardAllDrafts() {
        drafts = [:]
        notesChanged()
    }

    /// Writes the drafts into the deck's speaker notes in PowerPoint or Keynote and saves it there.
    func saveDraftsToDeck() {
        let toSave = DraftNotes.pruned(drafts, for: deckSlides)
        guard !toSave.isEmpty, let url = deckURL else { return }
        Task {
            do {
                if !powerPointReady {
                    try await app.open(url)
                    powerPointReady = true
                }
                let written = try await app.writeNotes(toSave)
                deckSlides = deckSlides.map { slide in
                    guard written.contains(slide.id), let notes = toSave[slide.id] else { return slide }
                    var s = slide
                    s.notes = notes
                    return s
                }
                drafts = drafts.filter { !written.contains($0.key) }
                notesChanged()
                let missed = toSave.keys.filter { !written.contains($0) }.sorted()
                notice = missed.isEmpty
                    ? "Saved notes for \(written.count) slide\(written.count == 1 ? "" : "s") into the deck in \(app.appName)."
                    : "Saved \(written.count) slides. Slide\(missed.count == 1 ? "" : "s") \(missed.map(String.init).joined(separator: ", ")) \(missed.count == 1 ? "has" : "have") no notes area in \(app.appName), so \(missed.count == 1 ? "its draft stays" : "their drafts stay") in Bema."
            } catch {
                notice = "The notes weren't saved into the deck: \(error.localizedDescription)"
            }
        }
    }

    /// The subscription route: Claude Desktop does the writing through Bema's MCP tools. Bema copies the
    /// request and opens Claude; the notes come back as drafts.
    func askClaudeApp(for ids: [Int]) {
        guard !ids.isEmpty else { return }
        if !BemaMCP.shared.enabled { BemaMCP.shared.enabled = true }
        let request = ClaudeAppRequest.text(slides: ids, deckName: deckName, allMissing: ids.count > 1)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(request, forType: .string)
        if let claude = NSWorkspace.shared.urlForApplication(withBundleIdentifier: ClaudeDesktop.bundleID) {
            NSWorkspace.shared.openApplication(at: claude, configuration: NSWorkspace.OpenConfiguration())
            notice = "The request is copied. Paste it into Claude (⌘V); the notes appear here as drafts."
        } else {
            notice = "The request is copied, but the Claude app isn't installed. Get it from claude.ai/download, connect it in Notes Writer settings, then paste."
        }
    }

    /// What the writer is told about a slide: its text from the slide previews, its neighbours' titles and,
    /// for writers that read pictures, the slide itself.
    func brief(for id: Int) -> SlideBrief {
        let slide = slides.first { $0.id == id }
        let visible = slides.filter { !$0.hidden }
        let i = visible.firstIndex { $0.id == id }
        return SlideBrief(deckName: deckName, number: id, count: slides.count,
                          title: slide?.title.replacingOccurrences(of: "\n", with: " ") ?? "",
                          text: slideText(for: id),
                          previousTitle: i.flatMap { $0 > 0 ? visible[$0 - 1].title : nil },
                          nextTitle: i.flatMap { $0 + 1 < visible.count ? visible[$0 + 1].title : nil },
                          picture: slidePNG(for: id))
    }

    /// Prompter, phone remote and anything else showing notes picks up the change; drafts are kept on disk.
    func notesChanged() {
        if let url = deckURL { DraftNotes.save(DraftNotes.pruned(drafts, for: deckSlides), for: url) }
        if !PrompterModel.shared.running { PrompterModel.shared.load(slides: slides) }
        RemoteServer.shared.deckChanged()
    }
}

/// The request copied for the Claude app.
enum ClaudeAppRequest {
    static func text(slides: [Int], deckName: String, allMissing: Bool) -> String {
        let deck = deckName.isEmpty ? "my presentation" : "my presentation “\(deckName)”"
        if allMissing {
            return "Use Bema to write speaker notes for the slides in \(deck) that have none. Look at each slide, then save the notes with Bema's set_speaker_notes tool."
        }
        return "Use Bema to write speaker notes for slide \(slides.first ?? 1) of \(deck). Look at the slide, then save the notes with Bema's set_speaker_notes tool."
    }
}
