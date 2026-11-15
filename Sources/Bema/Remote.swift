import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Network
import PDFKit

// MARK: - Live poll

@MainActor
final class PollModel: ObservableObject {
    static let shared = PollModel()

    @Published var question = "What should we cover next?"
    @Published var options: [String] = ["Option A", "Option B", "Option C"]
    @Published private(set) var votes: [Int] = [0, 0, 0]
    /// Shown on the audience screen (QR code to join, and live results).
    @Published var onScreen = false {
        didSet { if onScreen { RemoteServer.shared.ensureRunning() } }
    }
    @Published var showResults = true
    private var voters: [String: Int] = [:]

    var totalVotes: Int { votes.reduce(0, +) }

    func setOptions(_ new: [String]) {
        options = new
        reset()
    }

    func reset() {
        votes = Array(repeating: 0, count: options.count)
        voters = [:]
    }

    /// One vote per phone; voting again changes the vote.
    func vote(option: Int, voter: String) {
        guard options.indices.contains(option), !voter.isEmpty else { return }
        if votes.count != options.count { votes = Array(repeating: 0, count: options.count) }
        if let previous = voters[voter], votes.indices.contains(previous) { votes[previous] -= 1 }
        voters[voter] = option
        votes[option] += 1
    }
}

// MARK: - Local web server (phone remote + poll)

/// A tiny HTTP server on the local network. The remote and the poll each live under a random secret
/// path, so only people who scan the QR code can use them.
@MainActor
final class RemoteServer: ObservableObject {
    static let shared = RemoteServer()

    @Published var remoteEnabled = false {
        didSet { remoteEnabled ? ensureRunning() : stopIfUnused() }
    }
    @Published private(set) var port: UInt16?
    @Published private(set) var error: String?
    let remoteToken = RemoteServer.randomToken()
    let pollToken = RemoteServer.randomToken()
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "Bema.RemoteServer")

    var remoteURL: URL? { url(path: "/r/\(remoteToken)") }
    var pollURL: URL? { url(path: "/p/\(pollToken)") }

    private func url(path: String) -> URL? {
        guard let port, let ip = Self.localIPv4() else { return nil }
        return URL(string: "http://\(ip):\(port)\(path)")
    }

    func ensureRunning() {
        guard listener == nil else { return }
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: 8765) ?? .any)
            l.stateUpdateHandler = { [weak self] state in
                DispatchQueue.main.async {
                    guard let self else { return }
                    switch state {
                    case .ready: self.port = l.port?.rawValue; self.error = nil
                    case .failed(let e):
                        self.error = "The phone remote couldn't start: \(e.localizedDescription)"
                        self.listener = nil
                        self.port = nil
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
            self.error = "The phone remote couldn't start: \(error.localizedDescription)"
        }
    }

    private func stopIfUnused() {
        guard !remoteEnabled, !PollModel.shared.onScreen else { return }
        listener?.cancel()
        listener = nil
        port = nil
    }

    // MARK: HTTP

    nonisolated private static func receive(on conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, done, error in
            var buf = buffer
            if let data { buf.append(data) }
            if let request = HTTPRequest(buf) {
                Task { @MainActor in
                    let response = RemoteServer.shared.handle(request)
                    conn.send(content: response.data, completion: .contentProcessed { _ in conn.cancel() })
                }
            } else if done || error != nil || buf.count > 1_000_000 {
                conn.cancel()
            } else {
                receive(on: conn, buffer: buf)
            }
        }
    }

    private func handle(_ req: HTTPRequest) -> HTTPResponse {
        let parts = req.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return .notFound }
        let model = PresenterModel.shared

        if parts[0] == "r", parts[1] == remoteToken, remoteEnabled {
            if parts.count == 2 { return .html(RemotePage.html) }
            switch parts[2] {
            case "state":
                return .json(remoteState())
            case "cmd" where req.method == "POST":
                switch req.query["c"] {
                case "next": model.next()
                case "prev": model.previous()
                case "black": model.toggleBlack()
                case "first": model.first()
                case "last": model.last()
                case "start": model.startShow()
                case "prompter": PrompterModel.shared.toggle()
                case "timer": model.toggleTimer()
                case "confetti": model.fireReaction(.confetti)
                case "applause": model.fireReaction(.applause)
                default: return .badRequest
                }
                return .noContent
            case "slide" where parts.count == 4:
                let n = Int(parts[3].replacingOccurrences(of: ".jpg", with: "")) ?? model.current
                if let jpeg = slideJPEG(n) { return HTTPResponse(status: "200 OK", type: "image/jpeg", body: jpeg) }
                return .notFound
            default: return .notFound
            }
        }

        if parts[0] == "p", parts[1] == pollToken, PollModel.shared.onScreen {
            let poll = PollModel.shared
            if parts.count == 2 { return .html(PollPage.html) }
            switch parts[2] {
            case "state":
                return .json(["question": poll.question, "options": poll.options])
            case "vote" where req.method == "POST":
                poll.vote(option: Int(req.query["o"] ?? "") ?? -1, voter: String((req.query["v"] ?? "").prefix(40)))
                return .noContent
            default: return .notFound
            }
        }
        return .notFound
    }

    private func remoteState() -> [String: Any] {
        let m = PresenterModel.shared
        let next = m.nextSlide
        return [
            "deck": m.deckName,
            "presenting": m.phase == .presenting,
            "ready": m.powerPointReady,
            "slide": m.current,
            "position": m.visiblePosition,
            "count": m.visibleCount,
            "title": m.currentSlide?.title ?? "",
            "notes": NoteCues.plain(m.currentSlide?.notes ?? ""),
            "nextTitle": next?.title ?? "",
            "elapsed": Int(m.elapsed(at: Date())),
            "target": Int(m.targetSeconds),
            "timerRunning": m.timerStartedAt != nil,
            "black": m.audience == .black,
            "prompter": PrompterModel.shared.running,
        ]
    }

    private var jpegCache: [Int: Data] = [:]

    private func slideJPEG(_ id: Int) -> Data? {
        if let d = jpegCache[id] { return d }
        guard let img = PresenterModel.shared.image(for: id, width: 480),
              let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.75]) else { return nil }
        if jpegCache.count > 60 { jpegCache.removeAll() }
        jpegCache[id] = data
        return data
    }

    func deckChanged() { jpegCache.removeAll() }

    // MARK: Helpers

    nonisolated static func randomToken() -> String {
        let chars = Array("abcdefghjkmnpqrstuvwxyz23456789")
        return String((0..<10).map { _ in chars.randomElement()! })
    }

    /// The Mac's address on the local network (Wi-Fi or Ethernet).
    nonisolated static func localIPv4() -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var candidates: [(name: String, ip: String)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  (ifa.ifa_flags & UInt32(IFF_UP)) != 0, (ifa.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            let name = String(cString: ifa.ifa_name)
            let ip = String(cString: host)
            if name.hasPrefix("en") { candidates.append((name, ip)) }
        }
        return candidates.sorted { $0.name < $1.name }.first?.ip
    }

    static func qrCode(for string: String, size: CGFloat = 220) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]

    /// Parses a complete request head (we never need bodies: commands use the query string).
    init?(_ data: Data) {
        guard let text = String(data: data, encoding: .utf8), text.contains("\r\n\r\n"),
              let line = text.split(separator: "\r\n", maxSplits: 1).first else { return nil }
        let parts = line.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0])
        let comps = URLComponents(string: String(parts[1]))
        path = comps?.path ?? "/"
        var q: [String: String] = [:]
        for item in comps?.queryItems ?? [] { q[item.name] = item.value ?? "" }
        query = q
    }
}

struct HTTPResponse {
    let status: String
    let type: String
    let body: Data

    var data: Data {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\n"
        head += "Cache-Control: no-store\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n\r\n"
        return Data(head.utf8) + body
    }

    static func html(_ s: String) -> HTTPResponse { HTTPResponse(status: "200 OK", type: "text/html; charset=utf-8", body: Data(s.utf8)) }
    static func json(_ obj: [String: Any]) -> HTTPResponse {
        HTTPResponse(status: "200 OK", type: "application/json", body: (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8))
    }
    static let noContent = HTTPResponse(status: "204 No Content", type: "text/plain", body: Data())
    static let notFound = HTTPResponse(status: "404 Not Found", type: "text/plain", body: Data("Not found".utf8))
    static let badRequest = HTTPResponse(status: "400 Bad Request", type: "text/plain", body: Data("Bad request".utf8))
}

// MARK: - Phone pages

enum RemotePage {
    static let html = #"""
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover,user-scalable=no">
<meta name="theme-color" content="#0E1014"><title>Bema remote</title>
<style>
:root{--ground:#0E1014;--panel:#15181E;--raised:#1B1F27;--border:#232731;--text:#E9EBEF;--muted:#9BA3AF;--accent:#F5A524;--ink:#1A1206;--live:#FF5A4F}
*{box-sizing:border-box;-webkit-tap-highlight-color:transparent}
body{margin:0;background:var(--ground);color:var(--text);font:16px/1.45 -apple-system,system-ui,sans-serif;padding:calc(env(safe-area-inset-top) + 12px) 16px calc(env(safe-area-inset-bottom) + 16px)}
header{display:flex;justify-content:space-between;align-items:baseline;gap:12px}
.deck{font-weight:600;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.live{font:800 11px system-ui;letter-spacing:.08em;color:#FF8F87;background:#3A1A1A;border-radius:99px;padding:3px 8px}
.timer{font:600 28px ui-rounded,system-ui;font-variant-numeric:tabular-nums}
.muted{color:var(--muted);font-size:13px}
img{width:100%;aspect-ratio:16/9;object-fit:contain;background:#fff;border-radius:10px;margin:12px 0 4px;display:block}
.pos{display:flex;justify-content:space-between;align-items:baseline}
.pos b{font-size:22px}
.notes{background:var(--panel);border:1px solid var(--border);border-radius:12px;padding:14px;margin:10px 0 14px;font-size:18px;white-space:pre-wrap;max-height:34vh;overflow:auto}
.row{display:grid;grid-template-columns:1fr 2fr;gap:10px;margin-bottom:10px}
button{font:600 17px system-ui;border-radius:14px;border:1px solid var(--border);background:var(--raised);color:var(--text);min-height:64px}
button.next{background:var(--accent);color:var(--ink);border:none;font-size:22px;min-height:96px}
button.prev{min-height:96px}
.small{display:grid;grid-template-columns:repeat(4,1fr);gap:8px}
.small button{min-height:52px;font-size:14px}
button.on{outline:2px solid var(--accent)}
</style></head><body>
<header><span class="deck" id="deck">Bema</span><span id="live"></span></header>
<div class="pos"><span class="timer" id="timer">00:00</span><span class="muted" id="target"></span></div>
<img id="slide" alt="Current slide">
<div class="pos"><span><b id="position">–</b> <span class="muted" id="count"></span></span><span class="muted" id="next"></span></div>
<div class="notes" id="notes"></div>
<div class="row"><button class="prev" onclick="cmd('prev')">◀︎ Back</button><button class="next" onclick="cmd('next')">Next ▶︎</button></div>
<div class="small">
<button id="black" onclick="cmd('black')">Black</button>
<button onclick="cmd('timer')">Timer</button>
<button id="prompter" onclick="cmd('prompter')">Prompter</button>
<button onclick="cmd('confetti')">🎉</button>
</div>
<script>
const base=location.pathname.replace(/\/$/,'');let lastSlide=-1;
function fmt(s){s=Math.max(0,s|0);return String(s/60|0).padStart(2,'0')+':'+String(s%60).padStart(2,'0')}
async function cmd(c){if(navigator.vibrate)navigator.vibrate(15);await fetch(base+'/cmd?c='+c,{method:'POST'});refresh()}
async function refresh(){try{const r=await fetch(base+'/state');const s=await r.json();
deck.textContent=s.deck;live.innerHTML=s.presenting?'<span class="live">LIVE</span>':'';
timer.textContent=fmt(s.elapsed);target.textContent=s.target?'of '+fmt(s.target):'';
position.textContent=s.position;count.textContent='/ '+s.count;next.textContent=s.nextTitle?'Next: '+s.nextTitle:'';
notes.textContent=s.notes||'No notes for this slide.';black.classList.toggle('on',s.black);prompter.classList.toggle('on',s.prompter);
notes.dir=/[֐-ࣿ]/.test(s.notes)?'rtl':'ltr';
if(s.slide!==lastSlide){lastSlide=s.slide;slide.src=base+'/slide/'+s.slide+'.jpg'}}catch(e){}}
refresh();setInterval(refresh,1000);
</script></body></html>
"""#
}

enum PollPage {
    static let html = #"""
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<meta name="theme-color" content="#0E1014"><title>Vote</title>
<style>
body{margin:0;background:#0E1014;color:#E9EBEF;font:17px/1.45 -apple-system,system-ui,sans-serif;padding:calc(env(safe-area-inset-top) + 24px) 18px 24px}
h1{font-size:24px;line-height:1.25;margin:0 0 20px}
button{display:block;width:100%;text-align:left;font:600 18px system-ui;padding:18px;margin-bottom:10px;border-radius:14px;border:1px solid #2A2F3A;background:#181B22;color:#E9EBEF}
button.on{border:2px solid #F5A524;background:#2A2113}
p{color:#9BA3AF;font-size:14px}
</style></head><body>
<h1 id="q">Loading…</h1><div id="opts"></div><p id="msg"></p>
<script>
const base=location.pathname.replace(/\/$/,'');
let voter=localStorage.getItem('bemaVoter');if(!voter){voter=Math.random().toString(36).slice(2);localStorage.setItem('bemaVoter',voter)}
let mine=localStorage.getItem('bemaVote:'+base);let key='';
async function load(){const s=await (await fetch(base+'/state')).json();const k=JSON.stringify(s);if(k===key)return;key=k;
q.textContent=s.question;q.dir=/[֐-ࣿ]/.test(s.question)?'rtl':'ltr';opts.innerHTML='';
s.options.forEach((o,i)=>{const b=document.createElement('button');b.textContent=o;b.dir='auto';if(String(i)===mine)b.className='on';
b.onclick=async()=>{await fetch(base+'/vote?o='+i+'&v='+voter,{method:'POST'});mine=String(i);localStorage.setItem('bemaVote:'+base,mine);
[...opts.children].forEach((c,j)=>c.className=j===i?'on':'');msg.textContent='Thanks! You can change your vote.'};opts.appendChild(b)})}
load().catch(()=>{q.textContent='This poll is closed.'});setInterval(()=>load().catch(()=>{}),3000);
</script></body></html>
"""#
}
