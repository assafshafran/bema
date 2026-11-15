import AppKit
import CryptoKit
import SwiftUI

struct SlideTiming: Codable, Identifiable, Hashable {
    var id: Int
    var title: String
    var seconds: Double
    var budget: Double
    var words: Int
}

/// What happened in one run of a talk: time per slide against its budget, words and filler words.
struct TalkReport: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var deck: String
    var total: Double
    var target: Double
    var slides: [SlideTiming]
    var words: Int
    var fillers: [String: Int]
    var rehearsal: Bool

    var averageWPM: Int? {
        let spoken = slides.filter { $0.words > 0 }.reduce(0) { $0 + $1.seconds }
        return spoken > 30 && words > 0 ? Int(Double(words) / spoken * 60) : nil
    }
}

/// Pace, per-slide time budgets, the time-up cue, speech stats and rehearsal reports.
@MainActor
final class CoachModel: ObservableObject {
    static let shared = CoachModel()

    /// Listen while presenting to count speaking speed and filler words.
    @Published var listen: Bool = UserDefaults.standard.bool(forKey: "coachListen") {
        didSet { UserDefaults.standard.set(listen, forKey: "coachListen"); updateListening() }
    }
    /// Show the report when the show ends.
    @Published var rehearsalMode: Bool = UserDefaults.standard.bool(forKey: "rehearsalMode") {
        didSet { UserDefaults.standard.set(rehearsalMode, forKey: "rehearsalMode") }
    }
    @Published var timeCue: Bool = UserDefaults.standard.object(forKey: "timeCue") as? Bool ?? true {
        didSet { UserDefaults.standard.set(timeCue, forKey: "timeCue") }
    }
    @Published var cueSound: Bool = UserDefaults.standard.bool(forKey: "cueSound") {
        didSet { UserDefaults.standard.set(cueSound, forKey: "cueSound") }
    }

    @Published private(set) var cueFlashUntil: Date?
    @Published private(set) var slideStart: Date?
    @Published private(set) var lastReport: TalkReport?
    @Published var showingReport = false

    private var timings: [Int: Double] = [:]
    private var wordsBySlide: [Int: Int] = [:]
    private var lastWordTotal = 0
    private var cuesFired: Set<Int> = []
    private var tick: Timer?
    private var recording = false

    private var presenter: PresenterModel { PresenterModel.shared }

    init() {
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.everySecond() }
        }
    }

    // MARK: Budgets and pace

    private var budgetKey: String? { presenter.deckURL?.path }

    /// Seconds planned for each visible slide: your rehearsal timings if you saved them, otherwise the
    /// planned talk length shared out by how much is in each slide's notes.
    func budgets() -> [Int: Double] {
        let visible = presenter.slides.filter { !$0.hidden }
        guard !visible.isEmpty else { return [:] }
        if let key = budgetKey,
           let custom = (UserDefaults.standard.dictionary(forKey: "slideBudgets") as? [String: [String: Double]])?[key],
           !custom.isEmpty {
            var out: [Int: Double] = [:]
            for s in visible { out[s.id] = custom[String(s.id)] ?? 30 }
            return out
        }
        let target = presenter.targetSeconds
        guard target > 0 else { return [:] }
        let weights = visible.map { max(15.0, Double(ScriptText.tokens($0.notes).count)) }
        let sum = weights.reduce(0, +)
        var out: [Int: Double] = [:]
        for (s, w) in zip(visible, weights) { out[s.id] = target * w / sum }
        return out
    }

    var usingRehearsalBudgets: Bool {
        guard let key = budgetKey else { return false }
        return (UserDefaults.standard.dictionary(forKey: "slideBudgets") as? [String: [String: Double]])?[key] != nil
    }

    func plannedStart(of slide: Int, budgets: [Int: Double]) -> Double {
        presenter.slides.filter { !$0.hidden && $0.id < slide }.reduce(0) { $0 + (budgets[$1.id] ?? 0) }
    }

    func slideElapsed(at date: Date) -> Double {
        slideStart.map { date.timeIntervalSince($0) } ?? 0
    }

    /// Seconds behind (positive) or ahead (negative) of plan, while presenting with the timer running.
    func paceDelta(at date: Date) -> Double? {
        guard presenter.phase == .presenting, presenter.timerStartedAt != nil else { return nil }
        let b = budgets()
        guard let budget = b[presenter.current] else { return nil }
        let expected = plannedStart(of: presenter.current, budgets: b) + min(slideElapsed(at: date), budget)
        return presenter.elapsed(at: date) - expected
    }

    func saveRehearsalBudgets(from report: TalkReport) {
        guard let key = budgetKey else { return }
        var all = (UserDefaults.standard.dictionary(forKey: "slideBudgets") as? [String: [String: Double]]) ?? [:]
        all[key] = Dictionary(uniqueKeysWithValues: report.slides.map { (String($0.id), max(5, $0.seconds.rounded())) })
        UserDefaults.standard.set(all, forKey: "slideBudgets")
        objectWillChange.send()
    }

    func resetBudgets() {
        guard let key = budgetKey else { return }
        var all = (UserDefaults.standard.dictionary(forKey: "slideBudgets") as? [String: [String: Double]]) ?? [:]
        all[key] = nil
        UserDefaults.standard.set(all, forKey: "slideBudgets")
        objectWillChange.send()
    }

    // MARK: Show lifecycle (called by PresenterModel)

    func deckLoaded(_ url: URL) {
        lastReport = Self.loadReport(for: url)
    }

    func showStarted() {
        timings = [:]
        wordsBySlide = [:]
        cuesFired = []
        lastWordTotal = 0
        SpeechHub.shared.resetStats()
        slideStart = Date()
        recording = true
        updateListening()
    }

    func slideChanged(from old: Int, to new: Int) {
        guard recording else { return }
        let now = Date()
        if let start = slideStart { timings[old, default: 0] += now.timeIntervalSince(start) }
        slideStart = now
    }

    func showEnded() {
        guard recording else { return }
        recording = false
        if let start = slideStart { timings[presenter.current, default: 0] += Date().timeIntervalSince(start) }
        slideStart = nil
        countWords()
        updateListening()

        let b = budgets()
        let hub = SpeechHub.shared
        let slides = presenter.slides.filter { !$0.hidden }.map {
            SlideTiming(id: $0.id, title: $0.title.replacingOccurrences(of: "\n", with: " "),
                        seconds: timings[$0.id] ?? 0, budget: b[$0.id] ?? 0, words: wordsBySlide[$0.id] ?? 0)
        }
        let total = slides.reduce(0) { $0 + $1.seconds }
        guard total >= 5 else { return }
        let report = TalkReport(date: Date(), deck: presenter.deckName, total: total, target: presenter.targetSeconds,
                                slides: slides, words: hub.totalWords, fillers: hub.fillers, rehearsal: rehearsalMode)
        lastReport = report
        if let url = presenter.deckURL { Self.save(report, for: url) }
        if rehearsalMode { showingReport = true }
    }

    // MARK: Listening

    private func updateListening() {
        let hub = SpeechHub.shared
        if listen && recording {
            guard !hub.isUsed(by: .coach) else { return }
            Task {
                if let error = await hub.request(.coach, locale: PrompterModel.shared.speechLocale()) {
                    presenter.notice = error
                }
            }
        } else if hub.isUsed(by: .coach) {
            hub.release(.coach)
        }
    }

    private func countWords() {
        let hub = SpeechHub.shared
        let total = hub.totalWords + hub.partial.count
        let delta = total - lastWordTotal
        if delta > 0 { wordsBySlide[presenter.current, default: 0] += delta }
        lastWordTotal = max(lastWordTotal, total)
    }

    // MARK: Time cue

    private func everySecond() {
        if recording { countWords() }
        guard timeCue, presenter.phase == .presenting, presenter.timerStartedAt != nil, presenter.targetSeconds > 0 else { return }
        let remaining = presenter.targetSeconds - presenter.elapsed(at: Date())
        for mark in [60, 0] where remaining <= Double(mark) && !cuesFired.contains(mark) {
            cuesFired.insert(mark)
            if remaining > Double(mark) - 5 { cue() }
        }
    }

    /// A pulse on the timer, a tap on the trackpad and (if turned on) a soft sound.
    func cue() {
        cueFlashUntil = Date().addingTimeInterval(4)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        if cueSound, let sound = NSSound(named: "Tink") {
            sound.volume = 0.4
            sound.play()
        }
    }

    // MARK: Saving reports

    private static func reportURL(for deck: URL) -> URL {
        let hash = SHA256.hash(data: Data(deck.path.utf8)).map { String(format: "%02x", $0) }.joined().prefix(20)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bema/Reports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(hash).json")
    }

    private static func save(_ report: TalkReport, for deck: URL) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        try? enc.encode(report).write(to: reportURL(for: deck))
    }

    private static func loadReport(for deck: URL) -> TalkReport? {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: reportURL(for: deck)) else { return nil }
        return try? dec.decode(TalkReport.self, from: data)
    }
}

// MARK: - Views

func formatDuration(_ t: Double) -> String {
    let s = Int(abs(t).rounded())
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
}

/// "On pace", "1:20 behind", "0:45 ahead".
struct PaceLabel: View {
    @ObservedObject private var coach = CoachModel.shared
    let date: Date

    var body: some View {
        if let delta = coach.paceDelta(at: date) {
            let (text, color): (String, Color) = {
                if delta > 30 { return ("\(formatDuration(delta)) behind", Theme.liveSoft) }
                if delta < -30 { return ("\(formatDuration(delta)) ahead", Theme.ok) }
                return ("On pace", Theme.muted)
            }()
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(color).fixedSize()
                .help("Compared with the planned time for each slide")
        }
    }
}

/// Time on the current slide against its budget, with a thin bar.
struct SlideBudgetChip: View {
    @EnvironmentObject private var model: PresenterModel
    @ObservedObject private var coach = CoachModel.shared

    var body: some View {
        if model.phase == .presenting, let budget = coach.budgets()[model.current] {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let spent = coach.slideElapsed(at: context.date)
                let over = spent > budget
                HStack(spacing: 6) {
                    Text("\(formatDuration(spent)) / \(formatDuration(budget))")
                        .font(Theme.numeral(11, .semibold))
                        .foregroundStyle(over ? Theme.liveSoft : Theme.textSoft)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.border)
                        Capsule().fill(over ? Theme.live : Theme.accent).frame(width: 46 * min(spent / max(budget, 1), 1))
                    }
                    .frame(width: 46, height: 4)
                }
                .help(coach.usingRehearsalBudgets ? "Time on this slide, against your rehearsal timing" : "Time on this slide, against its share of the planned talk length")
            }
        }
    }
}

/// Live words per minute and filler count while the coach (or the voice prompter) is listening.
struct SpeechStatsLabel: View {
    @ObservedObject private var hub = SpeechHub.shared

    var body: some View {
        if hub.listening {
            HStack(spacing: 8) {
                Image(systemName: "waveform").foregroundStyle(Theme.ok)
                if let wpm = hub.wordsPerMinute {
                    Text("\(wpm) wpm").foregroundStyle(wpm > 170 ? Theme.warnStrong : Theme.textSoft)
                        .help(wpm > 170 ? "You're speaking fast" : "Speaking speed over the last 30 seconds")
                }
                Text("\(hub.fillerCount) fillers").foregroundStyle(Theme.muted)
                    .help(hub.fillers.isEmpty ? "No filler words so far" : hub.fillers.sorted { $0.value > $1.value }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", "))
            }
            .font(.system(size: 12, weight: .medium))
        }
    }
}

/// The report after a talk or rehearsal.
struct TalkReportView: View {
    @EnvironmentObject private var model: PresenterModel
    @ObservedObject private var coach = CoachModel.shared
    let report: TalkReport
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    CapsLabel(report.rehearsal ? "Rehearsal report" : "Talk report")
                    Text(report.deck).font(.system(size: 22, weight: .semibold))
                    Text(report.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(PillButtonStyle(kind: .normal)).keyboardShortcut(.cancelAction)
            }

            HStack(spacing: 12) {
                stat("Total time", formatDuration(report.total),
                     report.target > 0 ? "planned \(formatDuration(report.target))" : nil,
                     report.target > 0 && report.total > report.target + 30 ? Theme.liveSoft : Theme.text)
                stat("Speaking speed", report.averageWPM.map { "\($0) wpm" } ?? "–", report.averageWPM == nil ? "turn on Speech Coach to measure" : "130–160 is comfortable", Theme.text)
                stat("Filler words", "\(report.fillers.values.reduce(0, +))",
                     report.fillers.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) ×\($0.value)" }.joined(separator: ", ").nilIfEmpty,
                     Theme.text)
            }

            CapsLabel("Time per slide")
            ScrollView {
                VStack(spacing: 8) {
                    let maxSeconds = max(report.slides.map { max($0.seconds, $0.budget) }.max() ?? 1, 1)
                    ForEach(report.slides) { s in
                        HStack(spacing: 12) {
                            Text("\(s.id)").font(Theme.numeral(12, .semibold)).foregroundStyle(Theme.muted).frame(width: 24, alignment: .trailing)
                            Text(s.title.nilIfEmpty ?? "Slide \(s.id)").font(.system(size: 13)).lineLimit(1).frame(width: 200, alignment: .leading)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Theme.border).frame(height: 8)
                                    Capsule().fill(s.budget > 0 && s.seconds > s.budget * 1.2 ? Theme.live : Theme.accent)
                                        .frame(width: g.size.width * s.seconds / maxSeconds, height: 8)
                                    if s.budget > 0 {
                                        Rectangle().fill(Theme.text).frame(width: 2, height: 14)
                                            .offset(x: g.size.width * s.budget / maxSeconds - 1)
                                    }
                                }
                                .frame(maxHeight: .infinity)
                            }
                            .frame(height: 16)
                            Text(formatDuration(s.seconds)).font(Theme.numeral(12, .medium)).frame(width: 48, alignment: .trailing)
                            Text(s.budget > 0 ? formatDuration(s.budget) : "").font(Theme.numeral(12)).foregroundStyle(Theme.muted).frame(width: 44, alignment: .trailing)
                        }
                    }
                }
            }
            HStack {
                Text("The white tick is each slide's budget.").font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
                if coach.usingRehearsalBudgets {
                    Button("Go back to automatic budgets") { coach.resetBudgets() }.buttonStyle(PillButtonStyle(kind: .normal))
                }
                Button("Use these timings as slide budgets") { coach.saveRehearsalBudgets(from: report) }
                    .buttonStyle(PillButtonStyle(kind: .accent))
                    .help("Next time, Bema checks your pace against how long each slide took here")
            }
        }
        .padding(28)
        .frame(width: 760, height: 620)
        .background(Theme.panel)
        .foregroundStyle(Theme.text)
    }

    private func stat(_ title: String, _ value: String, _ detail: String?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            CapsLabel(title)
            Text(value).font(Theme.numeral(26)).foregroundStyle(color)
            Text(detail ?? " ").font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
    }
}
