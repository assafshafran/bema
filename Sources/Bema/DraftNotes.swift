import CryptoKit
import Foundation

/// Speaker notes written for slides that had none, kept by Bema per deck until the presenter saves them
/// into the deck or discards them. The deck itself is never changed without "Save to Deck".
enum DraftNotes {
    /// The deck's slides with drafts filled in where a slide has no notes of its own. A slide that has
    /// notes in the deck keeps them: a draft never replaces what the presenter wrote.
    static func merge(_ slides: [SlideInfo], _ drafts: [Int: String]) -> [SlideInfo] {
        slides.map { slide in
            guard slide.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let draft = drafts[slide.id], !draft.isEmpty else { return slide }
            var s = slide
            s.notes = draft
            s.draft = true
            return s
        }
    }

    /// Slides worth writing notes for: visible, with no notes and no draft yet.
    static func needingNotes(_ slides: [SlideInfo]) -> [Int] {
        slides.filter { !$0.hidden && $0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.id)
    }

    /// Drafts that still matter: dropped once the deck has its own notes for that slide, or the slide is gone.
    static func pruned(_ drafts: [Int: String], for slides: [SlideInfo]) -> [Int: String] {
        let empty = Set(slides.filter { $0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map(\.id))
        return drafts.filter { empty.contains($0.key) && !$0.value.isEmpty }
    }

    // MARK: Storage

    static func load(for deck: URL) -> [Int: String] {
        guard let data = try? Data(contentsOf: fileURL(for: deck)),
              let raw = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: raw.compactMap { k, v in Int(k).map { ($0, v) } })
    }

    static func save(_ drafts: [Int: String], for deck: URL) {
        let url = fileURL(for: deck)
        if drafts.isEmpty { try? FileManager.default.removeItem(at: url); return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let raw = Dictionary(uniqueKeysWithValues: drafts.map { (String($0.key), $0.value) })
        try? JSONEncoder().encode(raw).write(to: url, options: .atomic)
    }

    private static func fileURL(for deck: URL) -> URL {
        let hash = SHA256.hash(data: Data(CloudDeck.key(deck).utf8)).map { String(format: "%02x", $0) }.joined().prefix(24)
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Bema/Draft Notes/\(hash).json")
    }
}
