import AppKit
import Foundation
import Network

/// What the MCP tools see of the open deck. The app's model in practice; a stand-in in tests.
@MainActor
protocol MCPDeck {
    var mcpDeckName: String? { get }
    var mcpAppName: String { get }
    var mcpCurrentSlide: Int { get }
    var mcpSlides: [SlideInfo] { get }
    func mcpSlideText(_ id: Int) -> String
    func mcpSlidePNG(_ id: Int) -> Data?
    /// Stores notes as a draft. Returns why it couldn't, or nil.
    func mcpSetDraft(_ notes: String, slide: Int) -> String?
}

/// Bema's MCP server, so Claude Desktop (and other MCP apps) can read the slides and write speaker notes
/// with the person's own subscription. JSON-RPC, one message per line. Pure apart from the deck it's given.
@MainActor
enum MCPHandler {
    static let serverName = "bema"
    static let supportedVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    static let tools: [[String: Any]] = [
        ["name": "get_deck",
         "description": "The presentation open in Bema: every slide's number, title, text, speaker notes and whether the slide is hidden, plus the slide the presenter is on. Notes marked as drafts were written for Bema and aren't in the deck yet.",
         "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false]],
        ["name": "get_slide_image",
         "description": "A picture of one slide, to see charts, photos and layout that the text doesn't show.",
         "inputSchema": ["type": "object",
                         "properties": ["slide": ["type": "integer", "description": "Slide number, starting at 1."]],
                         "required": ["slide"], "additionalProperties": false]],
        ["name": "set_speaker_notes",
         "description": "Saves speaker notes for a slide that has none in the deck. Bema keeps them as a draft the presenter can edit, then save into the deck. Write what the presenter will say: a few short lines in the first person, plain text, in the slide's language. **Bold** one phrase to stress if useful.",
         "inputSchema": ["type": "object",
                         "properties": ["slide": ["type": "integer", "description": "Slide number, starting at 1."],
                                        "notes": ["type": "string", "description": "The speaker notes, one idea per line."]],
                         "required": ["slide", "notes"], "additionalProperties": false]],
    ]

    /// The response to one message, or nil for a notification (or something that isn't a request).
    static func handle(_ line: Data, deck: MCPDeck) -> Data? {
        guard let msg = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let id = msg["id"], let method = msg["method"] as? String else { return nil }
        let params = msg["params"] as? [String: Any] ?? [:]
        func result(_ r: [String: Any]) -> Data? { encode(["jsonrpc": "2.0", "id": id, "result": r]) }
        func failure(_ code: Int, _ message: String) -> Data? {
            encode(["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]])
        }
        switch method {
        case "initialize":
            let asked = params["protocolVersion"] as? String ?? ""
            return result(["protocolVersion": supportedVersions.contains(asked) ? asked : supportedVersions[1],
                           "capabilities": ["tools": [String: Any]()],
                           "serverInfo": ["name": serverName, "title": "Bema", "version": Self.appVersion],
                           "instructions": "Bema is the presenter app showing the user's slides. Use get_deck to read the presentation, get_slide_image to see a slide, and set_speaker_notes to give a slide notes. Notes you set stay as drafts in Bema until the presenter saves them into the deck."])
        case "ping":
            return result([:])
        case "tools/list":
            return result(["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            let args = params["arguments"] as? [String: Any] ?? [:]
            return result(call(name, args, deck: deck))
        default:
            return failure(-32601, "Method not found: \(method)")
        }
    }

    static func call(_ name: String, _ args: [String: Any], deck: MCPDeck) -> [String: Any] {
        func text(_ s: String, error: Bool = false) -> [String: Any] {
            ["content": [["type": "text", "text": s]], "isError": error]
        }
        guard let deckName = deck.mcpDeckName else {
            return text("No presentation is open in Bema. Ask the user to open one in Bema (or present the deck open in PowerPoint or Keynote) first.", error: true)
        }
        let slides = deck.mcpSlides
        let slideNumber = (args["slide"] as? NSNumber)?.intValue ?? Int(args["slide"] as? String ?? "")
        switch name {
        case "get_deck":
            let list: [[String: Any]] = slides.map { s in
                ["number": s.id, "title": s.title, "hidden": s.hidden, "notes": s.notes,
                 "notes_are_draft": s.draft, "text": deck.mcpSlideText(s.id)]
            }
            let info: [String: Any] = ["presentation": deckName, "app": deck.mcpAppName,
                                       "current_slide": deck.mcpCurrentSlide, "slide_count": slides.count, "slides": list]
            let data = (try? JSONSerialization.data(withJSONObject: info, options: [.prettyPrinted, .sortedKeys])) ?? Data()
            return text(String(decoding: data, as: UTF8.self))
        case "get_slide_image":
            guard let n = slideNumber, slides.contains(where: { $0.id == n }) else {
                return text("There's no slide \(slideNumber.map(String.init) ?? "with that number"). The deck has \(slides.count) slides.", error: true)
            }
            guard let png = deck.mcpSlidePNG(n) else {
                return text("Bema has no picture of slide \(n) (hidden slides and decks without previews have none).", error: true)
            }
            return ["content": [["type": "image", "data": png.base64EncodedString(), "mimeType": "image/png"]], "isError": false]
        case "set_speaker_notes":
            guard let n = slideNumber, slides.contains(where: { $0.id == n }) else {
                return text("There's no slide \(slideNumber.map(String.init) ?? "with that number"). The deck has \(slides.count) slides.", error: true)
            }
            let notes = (args["notes"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !notes.isEmpty else { return text("The notes are empty.", error: true) }
            if let why = deck.mcpSetDraft(notes, slide: n) { return text(why, error: true) }
            return text("Saved as a draft for slide \(n). The presenter sees it in Bema and can edit it or save it into the deck.")
        default:
            return text("Bema has no tool called \(name).", error: true)
        }
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    private static func encode(_ obj: [String: Any]) -> Data? {
        try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])
    }
}

extension PresenterModel: MCPDeck {
    var mcpDeckName: String? { deckURL == nil || slides.isEmpty ? nil : deckName }
    var mcpAppName: String { app.appName }
    var mcpCurrentSlide: Int { current }
    var mcpSlides: [SlideInfo] { slides }
    func mcpSlideText(_ id: Int) -> String { slideText(for: id) }
    func mcpSlidePNG(_ id: Int) -> Data? { slidePNG(for: id) }
    func mcpSetDraft(_ notes: String, slide: Int) -> String? {
        if let s = deckSlides.first(where: { $0.id == slide }),
           !s.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Slide \(slide) already has speaker notes in the deck, and Bema keeps those. Only slides without notes get drafts."
        }
        setDraft(notes, for: slide)
        return nil
    }
}

// MARK: - The socket Bema listens on

/// While "Let Claude read and write notes" is on, Bema listens on a socket in its Application Support
/// folder that only this user can open. `Bema --mcp`, started by Claude Desktop, relays to it.
@MainActor
final class BemaMCP: ObservableObject {
    static let shared = BemaMCP()

    @Published var enabled = UserDefaults.standard.bool(forKey: "mcpEnabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "mcpEnabled")
            enabled ? start() : stop()
        }
    }
    @Published private(set) var error: String?
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "Bema.MCP")

    nonisolated static var socketURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("Bema/mcp.sock")
    }

    func startIfEnabled() { if enabled { start() } }

    private func start() {
        guard listener == nil else { return }
        let path = Self.socketURL.path
        try? FileManager.default.createDirectory(at: Self.socketURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        unlink(path)
        do {
            let params = NWParameters.tcp
            params.requiredLocalEndpoint = .unix(path: path)
            let l = try NWListener(using: params)
            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    switch state {
                    case .ready:
                        chmod(path, 0o600)
                        self?.error = nil
                    case .failed(let e):
                        self?.error = "Claude can't connect: \(e.localizedDescription)"
                        self?.listener = nil
                    default: break
                    }
                }
            }
            l.newConnectionHandler = { [weak self] conn in
                conn.start(queue: self?.queue ?? .main)
                Self.receive(on: conn, buffer: Data())
            }
            l.start(queue: queue)
            listener = l
        } catch {
            self.error = "Claude can't connect: \(error.localizedDescription)"
        }
    }

    private func stop() {
        listener?.cancel()
        listener = nil
        unlink(Self.socketURL.path)
    }

    nonisolated private static func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { data, _, done, error in
            var buf = buffer
            if let data { buf.append(data) }
            var lines: [Data] = []
            while let nl = buf.firstIndex(of: 0x0A) {
                lines.append(buf[buf.startIndex..<nl])
                buf = Data(buf[buf.index(after: nl)...])
            }
            if !lines.isEmpty {
                Task { @MainActor in
                    for line in lines where !line.isEmpty {
                        if let response = MCPHandler.handle(Data(line), deck: PresenterModel.shared) {
                            conn.send(content: response + Data([0x0A]), completion: .contentProcessed { _ in })
                        }
                    }
                }
            }
            if done || error != nil || buf.count > 8 << 20 { conn.cancel(); return }
            receive(on: conn, buffer: buf)
        }
    }
}

// MARK: - `Bema --mcp`: the relay Claude Desktop starts

/// Relays MCP messages between Claude Desktop (stdin and stdout) and the running Bema (the socket).
/// Starts Bema in the background when it isn't running.
enum MCPBridge {
    static func run() -> Never {
        setvbuf(stdout, nil, _IOLBF, 0)
        var fd: Int32 = -1
        while let line = readLine(strippingNewline: true) {
            if line.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if fd < 0 { fd = connectOrLaunch() }
            if fd >= 0, send(fd, line + "\n") { continue }
            // Bema went away: try once more from the start.
            if fd >= 0 { close(fd) }
            fd = connectOrLaunch()
            if fd >= 0, send(fd, line + "\n") { continue }
            fd = -1
            replyUnavailable(to: line)
        }
        // stdin closed: give replies already on their way a moment to arrive.
        usleep(fd >= 0 ? 800_000 : 0)
        exit(0)
    }

    /// Connects to Bema, starting it if needed, and starts copying its replies to stdout.
    private static func connectOrLaunch() -> Int32 {
        if let fd = connect() { startReading(fd); return fd }
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launcher.arguments = ["-g", "-j", Bundle.main.bundleURL.path]
        try? launcher.run()
        for _ in 0..<60 {
            usleep(250_000)
            if let fd = connect() { startReading(fd); return fd }
        }
        return -1
    }

    private static func connect() -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let path = BemaMCP.socketURL.path
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let bytes = Array(path.utf8.prefix(raw.count - 1))
            raw.copyBytes(from: bytes + [0])
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        if ok != 0 { close(fd); return nil }
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    private static func startReading(_ fd: Int32) {
        Thread.detachNewThread {
            var buf = [UInt8](repeating: 0, count: 65536)
            while true {
                let n = read(fd, &buf, buf.count)
                if n <= 0 { return }
                FileHandle.standardOutput.write(Data(buf[0..<n]))
            }
        }
    }

    private static func send(_ fd: Int32, _ text: String) -> Bool {
        let data = Array(text.utf8)
        var sent = 0
        while sent < data.count {
            let n = data[sent...].withUnsafeBytes { Darwin.send(fd, $0.baseAddress, $0.count, 0) }
            if n <= 0 { return false }
            sent += n
        }
        return true
    }

    private static func replyUnavailable(to line: String) {
        guard let msg = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let id = msg["id"] else { return }
        let reply: [String: Any] = ["jsonrpc": "2.0", "id": id, "error": [
            "code": -32000,
            "message": "Bema isn't answering. Open Bema and turn on “Let Claude read and write notes” in Notes Writer settings."]]
        if let data = try? JSONSerialization.data(withJSONObject: reply) {
            FileHandle.standardOutput.write(data + Data([0x0A]))
        }
    }
}

// MARK: - Connecting Claude Desktop

/// Adds Bema to Claude Desktop's list of MCP servers (its claude_desktop_config.json).
enum ClaudeDesktop {
    static let bundleID = "com.anthropic.claudefordesktop"
    static let serverKey = "bema"

    static var configURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude_desktop_config.json")
    }

    static var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }

    /// The command that starts Bema's relay.
    static var command: String { Bundle.main.executablePath ?? "/Applications/Bema.app/Contents/MacOS/Bema" }

    /// For Claude Code and other apps that take a command line.
    static var claudeCodeCommand: String { "claude mcp add bema -- \"\(command)\" --mcp" }

    /// The config with Bema's entry added or updated, keeping everything else. Throws if the existing
    /// file isn't a JSON object (so it's never overwritten by mistake).
    static func adding(command: String, to existing: Data?) throws -> Data {
        var root: [String: Any] = [:]
        if let existing, !existing.isEmpty, !String(decoding: existing, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let obj = try JSONSerialization.jsonObject(with: existing) as? [String: Any] else {
                throw NoteWriterError.server("Claude's settings file isn't in the expected format, so Bema left it alone.")
            }
            root = obj
        }
        var servers = root["mcpServers"] as? [String: Any] ?? [:]
        servers[serverKey] = ["command": command, "args": ["--mcp"]]
        root["mcpServers"] = servers
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Whether the config already starts this copy of Bema.
    static func isConnected(_ data: Data?, command: String) -> Bool {
        guard let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = (root["mcpServers"] as? [String: Any])?[serverKey] as? [String: Any] else { return false }
        return entry["command"] as? String == command
    }

    static var isConnected: Bool { isConnected(try? Data(contentsOf: configURL), command: command) }

    /// Writes Bema into Claude Desktop's config, keeping a copy of the previous file.
    static func connect() throws {
        let url = configURL
        let existing = try? Data(contentsOf: url)
        let updated = try adding(command: command, to: existing)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let existing {
            try? existing.write(to: url.deletingLastPathComponent().appendingPathComponent("claude_desktop_config.before-bema.json"))
        }
        try updated.write(to: url, options: .atomic)
    }
}
