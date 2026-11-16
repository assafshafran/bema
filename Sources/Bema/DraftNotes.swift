import CryptoKit
import Foundation

/// Speaker notes changed in Bema and not yet in the deck: notes written for slides that had none, and
/// notes the presenter edited. Kept by Bema per deck until saved into the deck or discarded. The deck
/// itself is never changed without "Save to Deck".
enum DraftNotes {
    /// The deck's slides with their drafts in place of the deck's notes.
    static func merge(_ slides: [SlideInfo], _ drafts: [Int: String]) -> [SlideInfo] {
        slides.map { slide in
            guard let draft = drafts[slide.id], !draft.isEmpty,
                  same(draft, slide.notes) == false else { return slide }
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

    /// Drafts that still matter: dropped when the slide is gone or the deck already says the same.
    static func pruned(_ drafts: [Int: String], for slides: [SlideInfo]) -> [Int: String] {
        let deck = Dictionary(slides.map { ($0.id, $0.notes) }, uniquingKeysWith: { a, _ in a })
        return drafts.filter { id, text in
            guard let notes = deck[id] else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !same(text, notes)
        }
    }

    /// Notes that read the same apart from surrounding blank space and line-ending style.
    static func same(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String {
            s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return norm(a) == norm(b)
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
