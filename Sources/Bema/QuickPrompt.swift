import AppKit
import SwiftUI

/// The start screen's "Quick prompt": paste any text and prompt it in the detached prompter, no deck needed.
struct QuickPromptCard: View {
    @ObservedObject private var prompter = PrompterModel.shared
    @Environment(\.openWindow) private var openWindow
    @State private var text = ""

    private var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 40, height: 40)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.warnBg))
                VStack(alignment: .leading, spacing: 4) {
                    CapsLabel("Quick prompt · no deck needed", color: Theme.accent)
                    Text("Prompt any text").font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.textBright)
                    Text("Paste a script, a speech or talking points. Bema opens the prompter in its own window: it follows your voice, scrolls by itself or by hand, sits under your camera and stays hidden from screen sharing.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted)
                        .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .accessibilityLabel("Your text")
                if text.isEmpty {
                    Text("Paste or type what you want to say…")
                        .font(.system(size: 14)).foregroundStyle(Theme.dim)
                        .padding(.leading, 5).padding(.top, 1)
                        .allowsHitTesting(false)
                }
            }
            .frame(height: 104)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bar))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderStrong))

            HStack(spacing: 10) {
                Text(verbatim: QuickPrompt.summary(for: text))
                    .font(.system(size: 12)).foregroundStyle(Theme.dim)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Open empty prompter") {
                    prompter.editingOwnScript = true
                    openWindow(id: "prompter")
                }
                .buttonStyle(PillButtonStyle(kind: .normal, height: 34))
                .fixedSize()
                .help("Open the prompter on a box to paste or type your text")
                Button("Prompt this text") {
                    prompter.useOwnScript(text)
                    openWindow(id: "prompter")
                    text = ""
                }
                .buttonStyle(PillButtonStyle(kind: hasText ? .accent : .normal, height: 34))
                .fixedSize()
                .disabled(!hasText)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Open the prompter with this text (⌘↩)")
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.border))
    }
}

enum QuickPrompt {
    /// The line under the box: how long the text is, or what happens to it.
    static func summary(for text: String, wordsPerMinute: Double = 140) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace }).count
        guard words > 0 else { return "Remembered on this Mac only. **bold** and [pause] work as in notes." }
        let minutes = max(1, Int((Double(words) / wordsPerMinute).rounded()))
        return "\(words) word\(words == 1 ? "" : "s") · about \(minutes) min at a speaking pace"
    }
}

/// Right-clicking Bema's menu bar icon opens its panel, like a left click. SwiftUI's menu bar extra only
/// answers left clicks, so this watches Bema's own right clicks and clicks the icon's button for them.
@MainActor
enum MenuBarRightClick {
    private static var monitor: Any?

    static func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { event in
            guard let window = event.window, isStatusBarWindow(className: String(describing: type(of: window))),
                  let button = statusButton(in: window.contentView) else { return event }
            button.performClick(nil)
            return nil
        }
    }

    /// The menu bar item's window is AppKit's private NSStatusBarWindow.
    nonisolated static func isStatusBarWindow(className: String) -> Bool {
        className.hasPrefix("NSStatusBar") && className.hasSuffix("Window")
    }

    private static func statusButton(in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton { return button }
        for sub in view.subviews { if let b = statusButton(in: sub) { return b } }
        return nil
    }
}
