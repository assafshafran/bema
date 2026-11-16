import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Who writes speaker notes for slides that have none. Nothing is sent anywhere until the person picks a
/// writer and asks for notes; then only the slide's text (and, for writers that read pictures, the slide's
/// picture) goes to that writer.
enum NoteWriterKind: String, CaseIterable, Identifiable {
    /// Apple's on-device model (Apple Intelligence). Nothing leaves the Mac.
    case onDevice
    /// A model on this Mac or network that speaks the OpenAI chat API: Ollama, LM Studio.
    case local
    /// Claude through the Anthropic API, with the person's API key.
    case claude
    /// OpenAI's API, with the person's API key.
    case openAI
    /// The person's Claude subscription: Claude Desktop reads the slides from Bema over MCP and puts the
    /// notes back. Bema can't start that itself, so its button copies the request and opens Claude.
    case claudeApp

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: return "On this Mac (Apple Intelligence)"
        case .local: return "Local model (Ollama, LM Studio)"
        case .claude: return "Claude API key"
        case .openAI: return "OpenAI API key"
        case .claudeApp: return "Claude app (your subscription)"
        }
    }

    /// Short name for "Draft by …" and progress messages.
    var shortName: String {
        switch self {
        case .onDevice: return "Apple Intelligence"
        case .local: return "your local model"
        case .claude: return "Claude"
        case .openAI: return "OpenAI"
        case .claudeApp: return "Claude"
        }
    }

    /// Where the slide goes, in the person's words.
    var privacy: String {
        switch self {
        case .onDevice: return "Runs on this Mac. Nothing leaves it."
        case .local: return "Sent only to the server address below (on this Mac unless you change it)."
        case .claude: return "The slide's text and picture are sent to Anthropic with your key, only when you ask for notes."
        case .openAI: return "The slide's text and picture are sent to OpenAI with your key, only when you ask for notes."
        case .claudeApp: return "Claude reads the slides from Bema only while “Let Claude read and write notes” is on."
        }
    }

    /// Writers Bema calls itself (the Claude app is driven from Claude instead).
    var writesInBema: Bool { self != .claudeApp }
}

/// The writer settings, kept in UserDefaults. API keys are in the Keychain, never in UserDefaults.
struct NoteWriterSettings: Equatable {
    var kind: NoteWriterKind?
    var claudeModel = NoteWriterSettings.defaultClaudeModel
    var openAIModel = NoteWriterSettings.defaultOpenAIModel
    var localURL = NoteWriterSettings.defaultLocalURL
    var localModel = ""
    /// Most local models read text only, so pictures are off by default for them.
    var localSendsPicture = false

    static let defaultClaudeModel = "claude-opus-5-5"
    static let defaultOpenAIModel = "gpt-5"
    static let defaultLocalURL = "http://localhost:11434/v1"

    static func load(_ d: UserDefaults = .standard) -> NoteWriterSettings {
        var s = NoteWriterSettings()
        s.kind = d.string(forKey: "noteWriter").flatMap(NoteWriterKind.init(rawValue:))
        if let v = d.string(forKey: "noteWriterClaudeModel"), !v.isEmpty { s.claudeModel = v }
        if let v = d.string(forKey: "noteWriterOpenAIModel"), !v.isEmpty { s.openAIModel = v }
        if let v = d.string(forKey: "noteWriterLocalURL"), !v.isEmpty { s.localURL = v }
        s.localModel = d.string(forKey: "noteWriterLocalModel") ?? ""
        s.localSendsPicture = d.bool(forKey: "noteWriterLocalPicture")
        return s
    }

    func save(_ d: UserDefaults = .standard) {
        d.set(kind?.rawValue, forKey: "noteWriter")
        d.set(claudeModel, forKey: "noteWriterClaudeModel")
        d.set(openAIModel, forKey: "noteWriterOpenAIModel")
        d.set(localURL, forKey: "noteWriterLocalURL")
        d.set(localModel, forKey: "noteWriterLocalModel")
        d.set(localSendsPicture, forKey: "noteWriterLocalPicture")
    }
}

/// What the writer is told about one slide.
struct SlideBrief: Equatable {
    var deckName: String
    var number: Int
    var count: Int
    var title: String
    var text: String
    var previousTitle: String?
    var nextTitle: String?
    /// PNG of the slide, for writers that read pictures.
    var picture: Data?
}

enum NoteWriterError: LocalizedError, Equatable {
    case notSetUp
    case missingKey(String)
    case unavailable(String)
    case refused
    case empty
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notSetUp: return "Choose who writes your notes first."
        case .missingKey(let who): return "Add your \(who) API key in the notes writer settings."
        case .unavailable(let why): return why
        case .refused: return "The writer declined to write notes for this slide."
        case .empty: return "The writer returned no notes. Try again."
        case .server(let message): return message
        }
    }
}

// MARK: - Prompt (pure)

enum NotePrompt {
    static let instructions = """
    You write speaker notes for one slide of a presentation. The presenter reads them on a private screen \
    while speaking, so write what to say, not a description of the slide.
    - Write 3 to 6 short lines, in the first person, as the words to say to the audience. One idea per line.
    - Say the words themselves. Don't comment on the slide or the notes: no "I see", "this slide shows",     "I need to emphasize".
    - Explain and connect the points on the slide. If the next slide's title is given, end with a short,     natural bridge to it; never just "let's move to the next slide".
    - Don't invent numbers, names, dates or facts that the slide doesn't give.
    - Write in the language of the slide.
    - Plain text only: no headings, no bullets, no numbering, no quotation marks around the notes, no preamble. \
    You may put **two asterisks** around the one phrase to stress.
    """

    /// Slide text is cut so a slide with a lot of text still fits small on-device models.
    static let maxSlideText = 3000

    static func prompt(_ b: SlideBrief) -> String {
        var lines: [String] = []
        if !b.deckName.isEmpty { lines.append("Presentation: \(b.deckName)") }
        lines.append("Slide \(b.number) of \(b.count).")
        if let p = b.previousTitle, !p.isEmpty { lines.append("Previous slide: \(p)") }
        if let n = b.nextTitle, !n.isEmpty { lines.append("Next slide: \(n)") }
        lines.append("")
        if !b.title.isEmpty { lines.append("Title: \(b.title)") }
        let text = b.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            lines.append(b.picture == nil ? "The slide has no text." : "The slide has no text; the picture shows it.")
        } else {
            lines.append("Text on the slide:")
            lines.append(String(text.prefix(maxSlideText)))
        }
        if b.picture != nil, !text.isEmpty { lines.append("The attached picture shows the slide.") }
        lines.append("")
        lines.append("Write the speaker notes for this slide.")
        return lines.joined(separator: "\n")
    }

    /// Tidies what a model returns into notes: no code fences, preambles, bullets, numbering or headings.
    static func clean(_ output: String) -> String {
        var lines = output.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.hasPrefix("```") }
        // A preamble line such as "Speaker notes:" or "Here are the notes for slide 3:".
        if let first = lines.first(where: { !$0.isEmpty }), first.hasSuffix(":"), first.count < 80,
           let i = lines.firstIndex(of: first) {
            lines.remove(at: i)
        }
        lines = lines.map { line in
            var l = line
            while l.hasPrefix("#") { l.removeFirst() }
            for marker in ["- ", "• ", "* ", "– "] where l.hasPrefix(marker) { l.removeFirst(marker.count) }
            if let r = l.range(of: #"^\d{1,2}[.)]\s+"#, options: .regularExpression) { l.removeSubrange(r) }
            return l.trimmingCharacters(in: .whitespaces)
        }
        var text = lines.joined(separator: "\n")
        while text.contains("\n\n\n") { text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n") }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for (open, close) in [("\"", "\""), ("“", "”")] where text.hasPrefix(open) && text.hasSuffix(close) && text.count > 2 {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}

// MARK: - Requests and responses (pure)

enum ClaudeAPI {
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    static let version = "2026-10-21"
    static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// Models that take server-side fallbacks after a refusal.
    static let fallbackModels: Set<String> = ["claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5", "claude-fable-5-1", "claude-fable-5-2"]

    static func body(model: String, brief: SlideBrief) -> [String: Any] {
        var content: [[String: Any]] = []
        if let png = brief.picture {
            content.append(["type": "image", "source": ["type": "base64", "media_type": "image/png", "data": png.base64EncodedString()]])
        }
        content.append(["type": "text", "text": NotePrompt.prompt(brief)])
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 8000,
            "system": NotePrompt.instructions,
            "messages": [["role": "user", "content": content]],
        ]
        if fallbackModels.contains(model) {
            body["output_config"] = ["effort": "medium"]
            body["fallbacks"] = "default"
        }
        return body
    }

    static func headers(key: String, model: String) -> [String: String] {
        var h = ["x-api-key": key, "anthropic-version": version, "content-type": "application/json"]
        if fallbackModels.contains(model) { h["anthropic-beta"] = fallbackBeta }
        return h
    }

    static func parse(_ data: Data) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NoteWriterError.server("Claude sent an answer Bema couldn't read.")
        }
        if let error = json["error"] as? [String: Any] {
            throw NoteWriterError.server("Claude: \(error["message"] as? String ?? "the request failed.")")
        }
        if json["stop_reason"] as? String == "refusal" { throw NoteWriterError.refused }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NoteWriterError.empty }
        return text
    }
}

/// The OpenAI chat API, also spoken by Ollama and LM Studio.
enum ChatAPI {
    static let openAIBase = "https://api.openai.com/v1"

    static func endpoint(base: String) -> URL? {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        if b.hasSuffix("/chat/completions") { return URL(string: b) }
        return URL(string: b + "/chat/completions")
    }

    static func modelsEndpoint(base: String) -> URL? {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        return URL(string: b + "/models")
    }

    static func body(model: String, brief: SlideBrief, sendPicture: Bool) -> [String: Any] {
        let prompt = NotePrompt.prompt(sendPicture ? brief : { var b = brief; b.picture = nil; return b }())
        let user: Any
        if sendPicture, let png = brief.picture {
            user = [["type": "text", "text": prompt],
                    ["type": "image_url", "image_url": ["url": "data:image/png;base64," + png.base64EncodedString()]]]
        } else {
            user = prompt
        }
        return ["model": model,
                "messages": [["role": "system", "content": NotePrompt.instructions],
                             ["role": "user", "content": user]]]
    }

    static func parse(_ data: Data, who: String) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NoteWriterError.server("\(who) sent an answer Bema couldn't read.")
        }
        if let error = json["error"] as? [String: Any] {
            throw NoteWriterError.server("\(who): \(error["message"] as? String ?? "the request failed.")")
        }
        if let error = json["error"] as? String { throw NoteWriterError.server("\(who): \(error)") }
        let choice = (json["choices"] as? [[String: Any]])?.first
        let message = choice?["message"] as? [String: Any]
        if let refusal = message?["refusal"] as? String, !refusal.isEmpty { throw NoteWriterError.refused }
        guard let text = message?["content"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NoteWriterError.empty
        }
        return text
    }

    static func parseModels(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = json["data"] as? [[String: Any]] else { return [] }
        return list.compactMap { $0["id"] as? String }.sorted()
    }
}

// MARK: - Writing

enum NoteWriter {
    /// Writes notes for one slide with the chosen writer.
    static func write(_ brief: SlideBrief, settings: NoteWriterSettings) async throws -> String {
        guard let kind = settings.kind, kind.writesInBema else { throw NoteWriterError.notSetUp }
        let raw: String
        switch kind {
        case .onDevice:
            raw = try await onDevice(brief)
        case .claude:
            guard let key = Keychain.read(.claude), !key.isEmpty else { throw NoteWriterError.missingKey("Claude") }
            var req = URLRequest(url: ClaudeAPI.endpoint)
            req.httpMethod = "POST"
            ClaudeAPI.headers(key: key, model: settings.claudeModel).forEach { req.setValue($1, forHTTPHeaderField: $0) }
            req.httpBody = try JSONSerialization.data(withJSONObject: ClaudeAPI.body(model: settings.claudeModel, brief: brief))
            raw = try ClaudeAPI.parse(try await send(req))
        case .openAI:
            guard let key = Keychain.read(.openAI), !key.isEmpty else { throw NoteWriterError.missingKey("OpenAI") }
            raw = try await chat(base: ChatAPI.openAIBase, key: key, model: settings.openAIModel,
                                 brief: brief, picture: true, who: "OpenAI")
        case .local:
            guard !settings.localModel.isEmpty else {
                throw NoteWriterError.unavailable("Choose which local model writes your notes in the notes writer settings.")
            }
            raw = try await chat(base: settings.localURL, key: nil, model: settings.localModel,
                                 brief: brief, picture: settings.localSendsPicture, who: "The local model")
        case .claudeApp:
            throw NoteWriterError.notSetUp
        }
        let notes = NotePrompt.clean(raw)
        guard !notes.isEmpty else { throw NoteWriterError.empty }
        return notes
    }

    private static func chat(base: String, key: String?, model: String, brief: SlideBrief, picture: Bool, who: String) async throws -> String {
        guard let url = ChatAPI.endpoint(base: base) else { throw NoteWriterError.server("The server address isn't valid.") }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        if let key { req.setValue("Bearer \(key)", forHTTPHeaderField: "authorization") }
        req.httpBody = try JSONSerialization.data(withJSONObject: ChatAPI.body(model: model, brief: brief, sendPicture: picture))
        return try ChatAPI.parse(try await send(req), who: who)
    }

    private static func send(_ request: URLRequest) async throws -> Data {
        var req = request
        req.timeoutInterval = 180
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return data
        } catch let error as URLError where error.code == .cannotConnectToHost || error.code == .cannotFindHost {
            throw NoteWriterError.server("Couldn't reach \(req.url?.host ?? "the server"). If it's a local model, make sure Ollama or LM Studio is running.")
        }
    }

    /// The models a local server offers, for the settings menu.
    static func localModels(base: String) async -> [String] {
        guard let url = ChatAPI.modelsEndpoint(base: base) else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return [] }
        return ChatAPI.parseModels(data)
    }

    /// Whether Apple's on-device model can be used, and if not, why.
    static var onDeviceStatus: (ready: Bool, why: String) {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return (true, "")
            case .unavailable(.appleIntelligenceNotEnabled):
                return (false, "Turn on Apple Intelligence in System Settings to write notes on this Mac.")
            case .unavailable(.deviceNotEligible):
                return (false, "This Mac can't run Apple Intelligence. Choose another writer.")
            case .unavailable(.modelNotReady):
                return (false, "Apple Intelligence is still getting ready (downloading). Try again in a while.")
            default:
                return (false, "Apple Intelligence isn't available right now.")
            }
        }
        #endif
        return (false, "Writing notes on this Mac needs macOS 26 or later with Apple Intelligence.")
    }

    private static func onDevice(_ brief: SlideBrief) async throws -> String {
        let status = onDeviceStatus
        guard status.ready else { throw NoteWriterError.unavailable(status.why) }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            var textOnly = brief
            textOnly.picture = nil
            let session = LanguageModelSession(instructions: NotePrompt.instructions)
            do {
                return try await session.respond(to: NotePrompt.prompt(textOnly)).content
            } catch {
                throw NoteWriterError.server("Apple Intelligence couldn't write notes for this slide: \(error.localizedDescription)")
            }
        }
        #endif
        throw NoteWriterError.unavailable(status.why)
    }
}

// MARK: - Keychain

/// API keys, in the login Keychain.
enum Keychain {
    enum Account: String { case claude = "anthropic", openAI = "openai" }
    private static let service = "dev.getbema.Bema.note-writer"

    static func read(_ account: Account) -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account.rawValue, kSecReturnData as String: true]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ value: String, for account: Account) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                   kSecAttrAccount as String: account.rawValue]
        SecItemDelete(base as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var add = base
        add[kSecValueData as String] = Data(trimmed.utf8)
        SecItemAdd(add as CFDictionary, nil)
    }
}
