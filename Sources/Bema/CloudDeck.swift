import Foundation

/// A deck PowerPoint opened from OneDrive, SharePoint or Teams. PowerPoint reports a web address for it
/// instead of a file path, so Bema reads its notes and previews through PowerPoint rather than the file.
/// Pure, so it can be tested without PowerPoint.
enum CloudDeck {
    static func isCloud(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "")
    }

    /// The address for what PowerPoint reports as a presentation's full name, or nil when it isn't a web
    /// address (a file path, or "Presentation1" for a deck that was never saved).
    static func url(fromFullName fullName: String) -> URL? {
        let name = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = name.lowercased()
        guard lower.hasPrefix("https://") || lower.hasPrefix("http://") else { return nil }
        if let url = URL(string: name), url.host != nil { return url }
        guard let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed),
              let url = URL(string: encoded), url.host != nil else { return nil }
        return url
    }

    /// What a deck's saved timings and talk reports are stored under: the file's path (as before), or the
    /// web address for a cloud deck.
    static func key(_ url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    /// The ways PowerPoint may spell the address it reported, to find the open presentation again.
    static func fullNameCandidates(_ url: URL) -> [String] {
        var names = [url.absoluteString]
        if let decoded = url.absoluteString.removingPercentEncoding, decoded != names[0] { names.append(decoded) }
        return names
    }

    static let recordSeparator: Character = "\u{1E}"
    static let fieldSeparator: Character = "\u{1F}"

    /// Turns what PowerPoint's script returns (one record per slide: number, hidden, title, notes) into slides.
    /// PowerPoint separates paragraphs with a carriage return and line breaks with a vertical tab. The title
    /// is its first line, as when reading the file.
    static func parseSlides(_ output: String) -> [SlideInfo] {
        output.split(separator: recordSeparator, omittingEmptySubsequences: true).compactMap { record -> SlideInfo? in
            let f = record.split(separator: fieldSeparator, maxSplits: 3, omittingEmptySubsequences: false).map(String.init)
            guard f.count == 4, let n = Int(f[0].trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
            let title = lines(f[2]).components(separatedBy: "\n").first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            return SlideInfo(id: n, title: title.trimmingCharacters(in: .whitespaces),
                             notes: lines(f[3]),
                             hidden: f[1].trimmingCharacters(in: .whitespaces) == "true")
        }
    }

    private static func lines(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{0B}", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
