import AVFoundation
import Foundation
import Speech

/// One microphone stream into Apple's speech recognizer, shared by everything that listens:
/// the prompter, the speech coach, live captions and voice commands.
/// Recognition restarts every ~50 s (Apple limits a request to about a minute) and after pauses.
@MainActor
final class SpeechHub: ObservableObject {
    static let shared = SpeechHub()

    enum Consumer: Hashable { case prompter, coach, captions, commands }

    @Published private(set) var listening = false
    @Published private(set) var status: String?
    @Published private(set) var level: Float = 0
    /// Words of the utterance being recognized right now (revised as recognition improves).
    @Published private(set) var partial: [String] = []
    /// Finished utterances, newest last (kept short, for captions).
    @Published private(set) var recentUtterances: [String] = []

    // Totals for the speech coach.
    @Published private(set) var totalWords = 0
    @Published private(set) var fillers: [String: Int] = [:]
    private var samples: [(time: Date, words: Int)] = []

    /// Words from the deck to help recognition (names, product terms). Applied from the next request.
    var vocabulary: [String] = []

    /// Each consumer gets the current utterance's words on every update.
    var onWords: [Consumer: ([String]) -> Void] = [:]
    /// Called with the words of each finished utterance.
    var onUtterance: [Consumer: ([String]) -> Void] = [:]

    private var consumers: Set<Consumer> = []
    private var locale: Locale?
    /// Made fresh each time listening starts, so a newly picked microphone takes effect.
    private var engine = AVAudioEngine()
    /// The microphone the person picked (its unique id); nil uses the system default.
    @Published var microphoneID: String? = UserDefaults.standard.string(forKey: "microphoneID") {
        didSet {
            UserDefaults.standard.set(microphoneID, forKey: "microphoneID")
            restartForNewMicrophone()
        }
    }
    /// The name of the microphone being listened to, while listening.
    @Published private(set) var microphoneName: String?
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var restartTimer: Timer?
    private let box = RequestBox()
    private var tapInstalled = false

    final class RequestBox: @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?
        func set(_ r: SFSpeechAudioBufferRecognitionRequest?) { lock.lock(); request = r; lock.unlock() }
        func append(_ b: AVAudioPCMBuffer) { lock.lock(); request?.append(b); lock.unlock() }
        func end() { lock.lock(); request?.endAudio(); request = nil; lock.unlock() }
    }

    static let fillerWords: Set<String> = [
        "um", "umm", "uh", "uhh", "er", "erm", "ah", "hmm", "like", "basically", "actually", "literally", "so", "right",
        "אממ", "אה", "אהה", "כאילו", "בעצם", "יעני", "נו",
    ]
    static let fillerPhrases: [[String]] = [["you", "know"], ["sort", "of"], ["kind", "of"], ["i", "mean"], ["זאת", "אומרת"]]

    /// Words per minute over the last 30 seconds, while listening.
    var wordsPerMinute: Int? {
        guard listening, let last = samples.last else { return nil }
        let windowStart = last.time.addingTimeInterval(-30)
        guard let first = samples.first(where: { $0.time >= windowStart }), last.time.timeIntervalSince(first.time) > 8 else { return nil }
        return Int(Double(last.words - first.words) / last.time.timeIntervalSince(first.time) * 60)
    }

    var fillerCount: Int { fillers.values.reduce(0, +) }

    func resetStats() {
        totalWords = 0
        fillers = [:]
        samples = []
    }

    // MARK: Start / stop

    /// Starts listening for `consumer` (or adds it to a running session). Returns an error message, or nil.
    func request(_ consumer: Consumer, locale: Locale) async -> String? {
        consumers.insert(consumer)
        if listening, self.locale?.identifier == locale.identifier { return nil }
        if listening { stopEngine() }
        if let error = await startEngine(locale: locale) {
            consumers.remove(consumer)
            return error
        }
        return nil
    }

    func release(_ consumer: Consumer) {
        consumers.remove(consumer)
        onWords[consumer] = nil
        onUtterance[consumer] = nil
        if consumers.isEmpty { stopEngine() }
    }

    func isUsed(by consumer: Consumer) -> Bool { consumers.contains(consumer) }

    private func startEngine(locale: Locale) async -> String? {
        let speech = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard speech == .authorized else {
            return "Listening needs Speech Recognition permission: System Settings → Privacy & Security → Speech Recognition."
        }
        guard await AVCaptureDevice.requestAccess(for: .audio) else {
            return "Listening needs the microphone: System Settings → Privacy & Security → Microphone."
        }
        guard let r = SFSpeechRecognizer(locale: locale), r.isAvailable else {
            return "Speech recognition isn't available for \(Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)."
        }
        recognizer = r
        self.locale = locale

        // Only now, with listening on and the microphone allowed, is the input touched.
        engine = AVAudioEngine()
        let mics = CaptureDevices.microphones()
        let chosen = DeviceChoice.resolve(saved: microphoneID, available: mics)
        let input = engine.inputNode
        if let chosen, let deviceID = CaptureDevices.audioDeviceID(uid: chosen), let unit = input.audioUnit {
            var id = deviceID
            AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                                 &id, UInt32(MemoryLayout<AudioDeviceID>.size))
        }
        microphoneName = DeviceChoice.label(saved: microphoneID, available: mics, defaultName: CaptureDevices.defaultMicrophoneName)
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        let box = self.box
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            box.append(buffer)
            let level = Self.rms(buffer)
            DispatchQueue.main.async { self?.level = level }
        }
        tapInstalled = true
        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            tapInstalled = false
            return "Couldn't start the microphone: \(error.localizedDescription)"
        }
        listening = true
        let name = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
        status = r.supportsOnDeviceRecognition
            ? "Listening in \(name), on this Mac"
            : "Listening in \(name), using Apple's servers (not available offline for this language)"
        beginTask()
        return nil
    }

    /// A different microphone was picked while listening: listen again with it.
    private func restartForNewMicrophone() {
        guard listening, let locale else { return }
        stopEngine()
        Task { if let error = await startEngine(locale: locale) { status = error } }
    }

    private func stopEngine() {
        finishUtterance()
        listening = false
        microphoneName = nil
        status = nil
        level = 0
        restartTimer?.invalidate(); restartTimer = nil
        task?.cancel(); task = nil
        box.end()
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }

    private func beginTask() {
        guard listening, let recognizer else { return }
        finishUtterance()
        task?.cancel()
        box.end()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.contextualStrings = vocabulary
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        box.set(request)
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let heard = result?.bestTranscription.segments.map(\.substring)
            let isFinal = result?.isFinal ?? false
            DispatchQueue.main.async {
                guard let self, self.listening else { return }
                if let heard { self.update(heard) }
                if isFinal || error != nil {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.beginTask() }
                }
            }
        }
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.beginTask() }
        }
    }

    private func update(_ words: [String]) {
        partial = words
        samples.append((Date(), totalWords + words.count))
        if samples.count > 600 { samples.removeFirst(samples.count - 600) }
        for handler in onWords.values { handler(words) }
    }

    /// Counts the finished utterance into the totals and hands it to listeners.
    private func finishUtterance() {
        let words = partial
        partial = []
        guard !words.isEmpty else { return }
        totalWords += words.count
        let norm = words.map(ScriptText.normalize)
        for w in norm where Self.fillerWords.contains(w) { fillers[w, default: 0] += 1 }
        for phrase in Self.fillerPhrases where norm.count >= phrase.count {
            for i in 0...(norm.count - phrase.count) where Array(norm[i..<(i + phrase.count)]) == phrase {
                fillers[phrase.joined(separator: " "), default: 0] += 1
            }
        }
        recentUtterances.append(words.joined(separator: " "))
        if recentUtterances.count > 4 { recentUtterances.removeFirst() }
        for handler in onUtterance.values { handler(words) }
    }

    nonisolated private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0] else { return 0 }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return min(1, sqrt(sum / Float(n)) * 8)
    }
}
