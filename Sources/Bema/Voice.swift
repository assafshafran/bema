import Foundation
import SwiftUI

// MARK: - Voice commands

/// Spoken commands while presenting: "next slide", "previous slide", "go to slide 5",
/// "go to pricing" (matches a slide title), "black screen" — plus Hebrew equivalents.
@MainActor
final class VoiceCommands: ObservableObject {
    static let shared = VoiceCommands()

    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "voiceCommands") {
        didSet { UserDefaults.standard.set(enabled, forKey: "voiceCommands"); update() }
    }
    @Published private(set) var lastCommand: String?

    private var handled = 0          // words of the current utterance already acted on
    private var lastFired = Date.distantPast

    enum Command: Equatable { case next, previous, slide(Int), title(String), black }

    static let numbers: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17,
        "eighteen": 18, "nineteen": 19, "twenty": 20, "first": 1, "second": 2, "third": 3, "last": -1,
        "אחת": 1, "שתיים": 2, "שלוש": 3, "ארבע": 4, "חמש": 5, "שש": 6, "שבע": 7, "שמונה": 8, "תשע": 9, "עשר": 10,
    ]

    /// Finds a command in the words heard (normalized). `final` allows "go to <title>", which needs the whole phrase.
    static func parse(_ words: [String], final: Bool) -> Command? {
        let text = " " + words.joined(separator: " ") + " "
        func has(_ phrase: String) -> Bool { text.contains(" \(phrase) ") }
        if has("next slide") || has("שקופית הבאה") || has("השקופית הבאה") { return .next }
        if has("previous slide") || has("last slide please") || has("go back") || has("שקופית קודמת") || has("השקופית הקודמת") { return .previous }
        if has("black screen") || has("מסך שחור") { return .black }
        for (i, w) in words.enumerated() where (w == "slide" || w == "שקופית") && i + 1 < words.count {
            let n = words[i + 1]
            if let v = Int(n) ?? numbers[n] { return .slide(v) }
            if n == "number", i + 2 < words.count, let v = Int(words[i + 2]) ?? numbers[words[i + 2]] { return .slide(v) }
        }
        if final {
            for (i, w) in words.enumerated() where w == "goto" || (w == "go" && i + 1 < words.count && words[i + 1] == "to") || w == "עבור" {
                let start = w == "go" ? i + 2 : i + 1
                let rest = words.dropFirst(start).prefix(4).filter { !["the", "slide", "about", "ל", "אל"].contains($0) }
                if !rest.isEmpty { return .title(rest.joined(separator: " ")) }
            }
        }
        return nil
    }

    private func update() {
        let hub = SpeechHub.shared
        let model = PresenterModel.shared
        if enabled && model.phase == .presenting {
            guard !hub.isUsed(by: .commands) else { return }
            hub.onWords[.commands] = { [weak self] words in self?.heard(words, final: false) }
            hub.onUtterance[.commands] = { [weak self] words in self?.heard(words, final: true); self?.handled = 0 }
            Task {
                if let error = await hub.request(.commands, locale: PrompterModel.shared.speechLocale()) { model.notice = error }
            }
        } else if hub.isUsed(by: .commands) {
            hub.release(.commands)
        }
    }

    /// Called when the show starts or ends.
    func showChanged() { handled = 0; update() }

    private func heard(_ words: [String], final: Bool) {
        let norm = words.map(ScriptText.normalize).filter { !$0.isEmpty }
        if norm.count < handled { handled = 0 }
        let fresh = Array(norm.dropFirst(max(0, handled - 1)))
        guard Date().timeIntervalSince(lastFired) > 1.2, let command = Self.parse(fresh, final: final) else { return }
        handled = norm.count
        lastFired = Date()
        perform(command)
    }

    private func perform(_ command: Command) {
        let model = PresenterModel.shared
        switch command {
        case .next: model.next(); lastCommand = "Next slide"
        case .previous: model.previous(); lastCommand = "Previous slide"
        case .black: model.toggleBlack(); lastCommand = "Black screen"
        case .slide(let n):
            let visible = model.slides.filter { !$0.hidden }
            let target = n == -1 ? visible.last : (n >= 1 && n <= visible.count ? visible[n - 1] : nil)
            if let target { model.goTo(target.id); lastCommand = "Slide \(n == -1 ? visible.count : n)" }
        case .title(let query):
            if let slide = Self.bestTitleMatch(query, in: model.slides.filter { !$0.hidden }) {
                model.goTo(slide.id)
                lastCommand = "Go to “\(slide.title)”"
            }
        }
    }

    static func bestTitleMatch(_ query: String, in slides: [SlideInfo]) -> SlideInfo? {
        let q = ScriptText.tokens(query).map(ScriptText.normalize).filter { $0.count >= 3 }
        guard !q.isEmpty else { return nil }
        var best: (score: Int, slide: SlideInfo)?
        for s in slides {
            let t = ScriptText.tokens(s.title).map(ScriptText.normalize)
            let score = q.filter { qw in t.contains { ScriptAligner.similar(qw, $0) || $0.hasPrefix(qw) } }.count
            if score > 0, score > (best?.score ?? 0) { best = (score, s) }
        }
        return best?.slide
    }
}

// MARK: - Live captions

@MainActor
final class Captions: ObservableObject {
    static let shared = Captions()

    @Published var enabled: Bool = UserDefaults.standard.bool(forKey: "liveCaptions") {
        didSet { UserDefaults.standard.set(enabled, forKey: "liveCaptions"); update() }
    }

    func showChanged() { update() }

    private func update() {
        let hub = SpeechHub.shared
        let model = PresenterModel.shared
        if enabled && model.phase == .presenting {
            guard !hub.isUsed(by: .captions) else { return }
            Task {
                if let error = await hub.request(.captions, locale: PrompterModel.shared.speechLocale()) { model.notice = error }
            }
        } else if hub.isUsed(by: .captions) {
            hub.release(.captions)
        }
    }
}

/// Captions along the bottom of the audience slide: the last few words spoken.
struct CaptionsBar: View {
    @ObservedObject private var hub = SpeechHub.shared
    @ObservedObject private var captions = Captions.shared

    var body: some View {
        GeometryReader { geo in
            if captions.enabled, hub.listening {
                let words = (hub.recentUtterances.last.map { ScriptText.tokens($0) } ?? []) + hub.partial
                let shown = words.suffix(16).joined(separator: " ")
                if !shown.isEmpty {
                    Text(shown)
                        .font(.system(size: max(16, geo.size.width * 0.024), weight: .semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.72)))
                        .frame(maxWidth: geo.size.width * 0.8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, geo.size.height * 0.04)
                        .environment(\.layoutDirection, shown.isRightToLeft ? .rightToLeft : .leftToRight)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Note cues

/// Speaker-note markup: **bold**, *italic*, and cues in brackets like [pause], [smile], [slow], [click], [look up].
enum NoteCues {
    nonisolated(unsafe) static let cuePattern = try! Regex(#"\[([^\[\]\n]{1,24})\]"#, as: (Substring, Substring).self)

    /// Notes with markup applied, for the notes panel.
    static func attributed(_ notes: String, fontSize: Double) -> AttributedString {
        var out = AttributedString()
        var rest = Substring(notes)
        while let match = rest.firstMatch(of: cuePattern) {
            out += markdown(String(rest[rest.startIndex..<match.range.lowerBound]))
            var cue = AttributedString(" \(String(match.1).uppercased()) ")
            cue.font = .system(size: fontSize * 0.5, weight: .bold)
            cue.foregroundColor = Theme.accent
            cue.backgroundColor = Theme.accent.opacity(0.16)
            cue.baselineOffset = fontSize * 0.12
            out += cue
            rest = rest[match.range.upperBound...]
        }
        out += markdown(String(rest))
        return out
    }

    private static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    /// Notes with markup removed (for one-line previews).
    static func plain(_ notes: String) -> String {
        notes.replacing(cuePattern, with: "").replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "  ", with: " ")
    }
}
