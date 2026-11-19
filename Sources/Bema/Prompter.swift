import AVFoundation
import Foundation
import NaturalLanguage
import Speech
import SwiftUI

// MARK: - Script

struct ScriptWord: Identifiable, Hashable {
    let id: Int          // index in the whole script
    let text: String     // as written
    let norm: String     // normalized for matching speech
    let slide: Int
    var isCue = false   // [pause], [smile] … shown as a chip, never matched against speech
    var bold = false
    var isPlaceholder = false // "No notes for this slide": shown faintly, not to be read out
}

struct ScriptParagraph: Identifiable {
    let id: Int
    let slide: Int
    let slideTitle: String
    let isSlideStart: Bool
    let rtl: Bool
    let words: [ScriptWord]
}

enum ScriptText {
    /// Lowercase, no accents or Hebrew vowel points, letters and digits only.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return String(folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }

    /// Unusual words in the deck (product names, acronyms, CamelCase, names mid-sentence, long words),
    /// most frequent first. Given to the speech recognizer as hints so it hears them correctly.
    static func vocabulary(from slides: [SlideInfo], limit: Int = 100) -> [String] {
        var counts: [String: Int] = [:]
        for slide in slides {
            for text in [slide.title, slide.notes] {
                let tokens = tokens(text)
                for (i, raw) in tokens.enumerated() {
                    let w = raw.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
                    guard w.count >= 2 else { continue }
                    let letters = w.filter(\.isLetter)
                    let upperInside = w.dropFirst().contains { $0.isUppercase }
                    let allCaps = letters.count >= 2 && letters.allSatisfy { $0.isUppercase }
                    let mixedDigits = w.contains { $0.isNumber } && w.contains { $0.isLetter }
                    let previousEndsSentence = i == 0 || [".", "!", "?", ":"].contains(tokens[i - 1].last ?? ".")
                    let capitalizedMidSentence = (w.first?.isUppercase ?? false) && !previousEndsSentence
                    if upperInside || allCaps || mixedDigits || capitalizedMidSentence || w.count >= 11 {
                        counts[w, default: 0] += 1
                    }
                }
            }
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map(\.key)
    }
}

// MARK: - Matching speech to the script

/// Finds where in the script the speaker is, from the last few words recognized.
struct ScriptAligner {
    let words: [String]   // normalized script words

    /// Returns the index of the next word to read, or nil if the speech doesn't match nearby text.
    ///
    /// The last few words heard are aligned against the script ending at each nearby word, scoring
    /// matches and allowing skipped script words (you jumped ahead), extra spoken words (ad-libs,
    /// fillers), and words recognized split or joined ("Apple script" for "AppleScript").
    func align(heard: [String], from position: Int) -> Int? {
        let tail = Array(heard.map(ScriptText.normalize).filter { !$0.isEmpty }.suffix(8))
        guard let last = tail.last, !words.isEmpty else { return nil }
        let lo = max(0, position - 10)
        let hi = min(words.count - 1, position + 80)
        guard lo <= hi else { return nil }
        let heardRev = Array(tail.reversed())

        var best: (rank: Double, end: Int)?
        for end in lo...hi where endMatches(last: last, previous: tail.dropLast().last, at: end) {
            let segStart = max(0, end - (tail.count + 8) + 1)
            let scriptRev = Array(words[segStart...end].reversed())
            let score = Self.alignmentScore(heardRev, scriptRev)
            // Two solid matches, or one distinctive word just ahead of where we are.
            if score < 3.5 {
                guard score >= 2, last.count >= 5, end >= position - 1, end <= position + 4 else { continue }
            }
            let distance = Double(end >= position ? end - position : (position - end) * 3)
            let rank = score * 5 - distance * 0.15
            if best == nil || rank > best!.rank { best = (rank, end) }
        }
        return best.map { $0.end + 1 }
    }

    /// Whether the last word heard can be the script word at `end` (alone, or joined with the word before it).
    private func endMatches(last: String, previous: String?, at end: Int) -> Bool {
        let w = words[end]
        guard !w.isEmpty else { return false }
        if Self.similar(last, w) { return true }
        if let previous, Self.similar(previous + last, w) { return true }          // "apple" "script" → "applescript"
        if end > 0, !words[end - 1].isEmpty, Self.similar(last, words[end - 1] + w) { return true } // "powerpoint" → "power" "point"
        return false
    }

    /// Best score for aligning heard words with script words, both newest first and anchored at the newest.
    /// Match +2, split/joined match +2.5, skipped script word −0.4, extra heard word −0.7, mismatch −1.
    static func alignmentScore(_ heard: [String], _ script: [String]) -> Double {
        let n = heard.count, m = script.count
        let none = -Double.infinity
        var dp = Array(repeating: Array(repeating: none, count: m + 1), count: n + 1)
        dp[0][0] = 0
        var best = 0.0
        for i in 0...n {
            for j in 0...m where !(i == 0 && j == 0) {
                var v = none
                if i > 0, j > 0, dp[i - 1][j - 1] > none {
                    v = max(v, dp[i - 1][j - 1] + (similar(heard[i - 1], script[j - 1]) && !script[j - 1].isEmpty ? 2 : -1))
                }
                // Two heard words make one script word (heard newest-first: earlier word is heard[i-1]).
                if i > 1, j > 0, dp[i - 2][j - 1] > none, !script[j - 1].isEmpty, similar(heard[i - 1] + heard[i - 2], script[j - 1]) {
                    v = max(v, dp[i - 2][j - 1] + 2.5)
                }
                // One heard word makes two script words.
                if i > 0, j > 1, dp[i - 1][j - 2] > none, !script[j - 1].isEmpty, similar(heard[i - 1], script[j - 1] + script[j - 2]) {
                    v = max(v, dp[i - 1][j - 2] + 2.5)
                }
                if j > 0, dp[i][j - 1] > none { v = max(v, dp[i][j - 1] - (script[j - 1].isEmpty ? 0 : 0.4)) }
                if i > 0, dp[i - 1][j] > none { v = max(v, dp[i - 1][j] - 0.7) }
                dp[i][j] = v
                if v > best { best = v }
            }
        }
        return best
    }

    static func similar(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let la = a.count, lb = b.count
        guard min(la, lb) >= 4 else { return false }
        if a.hasPrefix(b) || b.hasPrefix(a) { return abs(la - lb) <= 2 }
        let limit = min(la, lb) >= 8 ? 2 : 1
        return abs(la - lb) <= limit && levenshtein(a, b, limit: limit) <= limit
    }

    private static func levenshtein(_ a: String, _ b: String, limit: Int) -> Int {
        let a = Array(a), b = Array(b)
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            var rowMin = cur[0]
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                rowMin = min(rowMin, cur[j])
            }
            if rowMin > limit { return limit + 1 }
            prev = cur
        }
        return prev[b.count]
    }
}

// MARK: - Steadying the voice position

/// Turns the jittery stream of "where the speaker is" guesses into a steady target.
/// Speech recognition keeps revising its last words, so raw matches wobble back and forth.
struct VoiceTarget {
    private(set) var index: Int
    private var pending: Int?
    private var pendingEvidence = -1

    init(_ index: Int = 0) { self.index = index }

    /// Offers a new match. `evidence` identifies what was heard (e.g. the number of words so far);
    /// a big jump is only confirmed by a match made after hearing something new.
    /// Returns true if the target moved.
    mutating func propose(_ next: Int, evidence: Int = Int.random(in: 0...Int.max)) -> Bool {
        let delta = next - index
        if delta == 0 { pending = nil; return false }
        // Recognition revising a word or two: never step back for that.
        if delta < 0 && delta >= -3 { return false }
        // Normal reading: move ahead.
        if delta > 0 && delta <= 25 { index = next; pending = nil; return true }
        // A big jump back or far ahead must be confirmed by the next match agreeing.
        if let p = pending, abs(p - next) <= 2 {
            if evidence == pendingEvidence { return false }   // same words heard again: not new evidence
            index = next; pending = nil; return true
        }
        pending = next
        pendingEvidence = evidence
        return false
    }

    mutating func reset(to i: Int) { index = i; pending = nil }
}

// MARK: - Prompter state

@MainActor
final class PrompterModel: ObservableObject {
    static let shared = PrompterModel()

    enum Mode: String, CaseIterable, Identifiable {
        case voice, auto, manual
        var id: String { rawValue }
        var label: String {
            switch self {
            case .voice: return "Voice"
            case .auto: return "Auto"
            case .manual: return "Manual"
            }
        }
    }

    enum Language: String, CaseIterable, Identifiable {
        case automatic, english, hebrew
        var id: String { rawValue }
        var label: String {
            switch self {
            case .automatic: return "Detect language"
            case .english: return "English"
            case .hebrew: return "Hebrew"
            }
        }
    }

    @Published private(set) var paragraphs: [ScriptParagraph] = []
    @Published private(set) var words: [ScriptWord] = []
    /// Index of the next word to read. Fractional while auto-scrolling.
    @Published var position: Double = 0 { didSet { positionChanged() } }
    @Published var mode: Mode = Mode(rawValue: UserDefaults.standard.string(forKey: "prompterMode") ?? "") ?? .voice {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "prompterMode"); if running { restart() } }
    }
    @Published private(set) var running = false
    @Published var wordsPerMinute: Double = UserDefaults.standard.object(forKey: "prompterWPM") as? Double ?? 140 {
        didSet { UserDefaults.standard.set(wordsPerMinute, forKey: "prompterWPM") }
    }
    @Published var followSlides: Bool = UserDefaults.standard.object(forKey: "prompterFollowSlides") as? Bool ?? true {
        didSet { UserDefaults.standard.set(followSlides, forKey: "prompterFollowSlides") }
    }
    @Published var mirrored = false
    @Published var language: Language = .automatic { didSet { if running && mode == .voice { restart() } } }
    @Published private(set) var status: String?
    /// Text pasted into the prompter, prompted instead of the deck's notes. nil: the deck's notes.
    @Published private(set) var ownScript: String?
    /// The detached prompter shows the box to paste your own text.
    @Published var editingOwnScript = false
    private var deckSlides: [SlideInfo] = []

    private var aligner = ScriptAligner(words: [])
    /// Where speech says you are. The displayed `position` glides toward it.
    private var voiceTarget = VoiceTarget()
    private var lastGlide = Date()
    /// When the target moved forward recently, to measure your speaking pace.
    private var advances: [(time: Date, index: Int)] = []
    private var lastVoiceActivity = Date.distantPast
    private var ticker: Timer?
    /// Set while the prompter itself moves the slideshow, so the slide change doesn't jump the script back.
    private var slideMovedByPrompter: Int?

    /// Shown, as a cue, in place of a slide's script when the slide has no speaker notes.
    static let noNotesCue = "No notes for this slide"

    var currentWordIndex: Int { min(Int(position), max(words.count - 1, 0)) }

    // MARK: Loading

    /// The deck's notes became available or changed. While you're prompting your own text, it stays.
    func load(slides: [SlideInfo]) {
        deckSlides = slides
        guard ownScript == nil else { return }
        build(slides)
    }

    /// Prompt pasted text instead of the deck's notes (no deck needed). Empty text goes back to the deck.
    func useOwnScript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { useDeckNotes(); return }
        ownScript = trimmed
        UserDefaults.standard.set(trimmed, forKey: Self.ownScriptKey)
        editingOwnScript = false
        build(Self.slides(forOwnScript: trimmed))
    }

    /// Back to the open deck's speaker notes.
    func useDeckNotes() {
        ownScript = nil
        editingOwnScript = false
        build(deckSlides)
    }

    /// The last text you prompted, to start the editor with.
    var lastOwnScript: String { ownScript ?? UserDefaults.standard.string(forKey: Self.ownScriptKey) ?? "" }
    var hasDeckNotes: Bool { deckSlides.contains { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    static let ownScriptKey = "prompterOwnScript"

    /// Your own text is one "slide" numbered 0: no slide headings, nothing to follow in a slideshow.
    static func slides(forOwnScript text: String) -> [SlideInfo] {
        [SlideInfo(id: 0, title: "", notes: text, hidden: false)]
    }

    private func build(_ slides: [SlideInfo]) {
        stop()
        var paras: [ScriptParagraph] = []
        var all: [ScriptWord] = []
        var pid = 0
        let shown = slides.filter { !$0.hidden }
        let deckHasNotes = shown.contains { !$0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        for slide in shown {
            let lines = slide.notes.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            // A slide without notes still gets its place in the script, so it isn't skipped unnoticed.
            if lines.isEmpty, deckHasNotes {
                let w = ScriptWord(id: all.count, text: Self.noNotesCue, norm: "", slide: slide.id, isCue: true, isPlaceholder: true)
                all.append(w)
                paras.append(ScriptParagraph(id: pid, slide: slide.id, slideTitle: slide.title.replacingOccurrences(of: "\n", with: " "),
                                             isSlideStart: true, rtl: false, words: [w]))
                pid += 1
                continue
            }
            for (i, line) in lines.enumerated() {
                // Keep multi-word cues like [look up] as one token.
                let joined = line.replacing(NoteCues.cuePattern) { m in "[" + m.1.replacingOccurrences(of: " ", with: "_") + "]" }
                var boldOn = false
                let ws = ScriptText.tokens(joined).map { raw -> ScriptWord in
                    var token = raw
                    if token.hasPrefix("["), token.hasSuffix("]"), token.count > 2 {
                        let label = String(token.dropFirst().dropLast()).replacingOccurrences(of: "_", with: " ").uppercased()
                        let w = ScriptWord(id: all.count, text: label, norm: "", slide: slide.id, isCue: true)
                        all.append(w)
                        return w
                    }
                    var bold = boldOn
                    if token.hasPrefix("**") { token.removeFirst(2); bold = true; boldOn = true }
                    if token.hasSuffix("**") || token.dropLast().hasSuffix("**") {
                        token = token.replacingOccurrences(of: "**", with: "")
                        bold = true
                        boldOn = false
                    }
                    let w = ScriptWord(id: all.count, text: token, norm: ScriptText.normalize(token), slide: slide.id, bold: bold)
                    all.append(w)
                    return w
                }
                paras.append(ScriptParagraph(id: pid, slide: slide.id, slideTitle: slide.title.replacingOccurrences(of: "\n", with: " "),
                                             isSlideStart: i == 0, rtl: line.isRightToLeft, words: ws))
                pid += 1
            }
        }
        paragraphs = paras
        words = all
        aligner = ScriptAligner(words: all.map(\.norm))
        SpeechHub.shared.vocabulary = ScriptText.vocabulary(from: slides)
        setPosition(0)
    }

    // MARK: Running

    func toggle() { running ? stop() : start() }

    func start() {
        guard !words.isEmpty else {
            status = ownScript == nil ? "This deck has no speaker notes to prompt from." : "There's no text to prompt."
            return
        }
        running = true
        status = nil
        switch mode {
        case .voice: startListening()
        case .auto: startTicker()
        case .manual: status = "Drag the script or click a word to move"
        }
    }

    func stop() {
        running = false
        ticker?.invalidate(); ticker = nil
        SpeechHub.shared.release(.prompter)
        if mode == .voice { status = nil }
    }

    private func restart() { stop(); start() }

    /// Moves the displayed position smoothly toward where speech says you are, 60 times a second,
    /// so the script flows instead of hopping from word to word.
    private func startGlide() {
        ticker?.invalidate()
        lastGlide = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.glide() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    private func glide() {
        guard running, mode == .voice else { return }
        let now = Date()
        let dt = min(now.timeIntervalSince(lastGlide), 0.1)
        lastGlide = now
        if SpeechHub.shared.level > 0.06 { lastVoiceActivity = now }
        let target = Double(voiceTarget.index)
        let goal = target + lead(at: now)
        // Never drift backward while following your voice: when recognition stalls, hold still.
        // Only a confirmed jump back (the target well behind) moves the script up.
        if goal < position && target > position - 3 { return }
        let diff = goal - position
        guard abs(diff) > 0.002 else { return }
        // Ease toward the goal quickly (time constant ~0.15 s), with a speed limit so it never lurches.
        let eased = diff * (1 - exp(-dt / 0.15))
        let limit = (abs(diff) > 8 ? 60.0 : 16.0) * dt
        position += max(-limit, min(limit, eased))
    }

    /// Speech recognition reports words about half a second late. While you're speaking, run a little
    /// ahead at your recent pace to make up for it; settle back when you pause.
    private func lead(at now: Date) -> Double {
        let recent = advances.filter { now.timeIntervalSince($0.time) < 4 }
        guard now.timeIntervalSince(lastVoiceActivity) < 0.5,
              let first = recent.first, let last = recent.last,
              last.time.timeIntervalSince(first.time) > 0.8 else { return 0 }
        let wordsPerSecond = Double(last.index - first.index) / last.time.timeIntervalSince(first.time)
        let sinceLastWord = now.timeIntervalSince(last.time)
        // Look ahead by part of the recognition lag, up to 1.5 words: enough to feel in step, not to run away.
        return max(0, min(1.5, wordsPerSecond * (0.3 + min(sinceLastWord, 0.3))))
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.running else { return }
                let next = self.position + self.wordsPerMinute / 60 / 30
                if next >= Double(self.words.count) { self.stop(); return }
                self.position = next
            }
        }
    }

    private func startListening() {
        voiceTarget.reset(to: currentWordIndex)
        SpeechHub.shared.onWords[.prompter] = { [weak self] heard in
            guard let self, self.running, self.mode == .voice else { return }
            self.lastVoiceActivity = Date()
            if let next = self.aligner.align(heard: heard, from: self.voiceTarget.index),
               self.voiceTarget.propose(min(next, self.words.count), evidence: heard.count) {
                self.advances.append((Date(), self.voiceTarget.index))
                if self.advances.count > 30 { self.advances.removeFirst(self.advances.count - 30) }
            }
        }
        startGlide()
        Task {
            if let error = await SpeechHub.shared.request(.prompter, locale: speechLocale()) {
                status = error
                running = false
            }
        }
    }

    /// The language to listen in: chosen in the prompter, or detected from the speaker notes.
    func speechLocale() -> Locale {
        switch language {
        case .english: return Locale(identifier: "en-US")
        case .hebrew: return Locale(identifier: "he-IL")
        case .automatic:
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(words.prefix(400).map(\.text).joined(separator: " "))
            switch recognizer.dominantLanguage {
            case .hebrew?: return Locale(identifier: "he-IL")
            case let lang?:
                let current = Locale.current
                if current.language.languageCode?.identifier == lang.rawValue { return current }
                return Locale(identifier: lang.rawValue)
            case nil: return Locale.current
            }
        }
    }

    // MARK: Slides

    private func positionChanged() {
        guard running, followSlides, ownScript == nil, !words.isEmpty else { return }
        let presenter = PresenterModel.shared
        guard presenter.phase == .presenting else { return }
        let slide = words[currentWordIndex].slide
        if slide != presenter.current {
            slideMovedByPrompter = slide
            presenter.goTo(slide)
        }
    }

    /// The slideshow moved (clicker, keyboard, PowerPoint): jump the script to that slide's text.
    func slideChanged(to slide: Int) {
        if slideMovedByPrompter == slide { slideMovedByPrompter = nil; return }
        guard ownScript == nil, !words.isEmpty, words[currentWordIndex].slide != slide,
              let first = words.first(where: { $0.slide == slide }) ?? words.first(where: { $0.slide > slide })
        else { return }
        setPosition(Double(first.id))
    }

    func jump(to wordIndex: Int) {
        setPosition(Double(max(0, min(wordIndex, words.count - 1))))
    }

    /// Moves the script directly (click, drag, slide change); voice following continues from here.
    func setPosition(_ p: Double) {
        position = max(0, p)
        voiceTarget.reset(to: Int(position.rounded()))
        advances.removeAll()
    }
}

