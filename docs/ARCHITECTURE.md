# Architecture

Bema is one SwiftUI app (a Swift package, `Sources/Bema`) with no dependencies beyond Apple's frameworks.

## The idea

PowerPoint or Keynote keeps running the slideshow, so everything the audience sees (animations, transitions, video, fonts) is exactly what the presentation app renders. Bema never re-renders slides for the audience. It:

1. **opens the deck in the presentation app** and reads its slides and speaker notes,
2. **runs the slideshow in a window** that it places on the audience display and makes full screen,
3. **follows and drives the show** (next, previous, jump, black screen) through AppleScript, polling the current slide a few times a second,
4. **draws its own layer over the audience slide** (pointer, drawings, captions, poll, camera) in a transparent, click-through panel,
5. shows the presenter everything else in its own window.

## Presentation apps

`SlideshowController` (`SlideshowApp.swift`) is the interface; there are two implementations.

| | PowerPoint (`PowerPointController.swift`) | Keynote (`KeynoteController` in `SlideshowApp.swift`) |
|---|---|---|
| Slides and notes | Read from the `.pptx` XML (`PPTXReader.swift`); for a deck opened from OneDrive, SharePoint or Teams (a web address, no file), through PowerPoint's AppleScript (`CloudDeck.swift`) | Read through Keynote's AppleScript |
| Writing notes into the deck | The notes page's body placeholder, then `save` | `presenter notes`, then `save` |
| Previews | PowerPoint's PDF export | Keynote's PDF export, skipped slides included |
| Starting the show | Show type "window", then window bounds by AppleScript | **Play → Play Slideshow in Window** pressed through Accessibility |
| Full screen on the chosen display | Accessibility `AXFullScreen` on the slideshow window | The same |
| Jump to a slide | Step next/previous until there (PowerPoint's `go to slide` fails during a show on Mac) | Keynote's slide switcher |
| Black / white screen | PowerPoint's slide state | Drawn by Bema on its overlay |

Windowed shows are used so the app's own presenter view never appears and never covers Bema. All AppleScript runs on one serial queue per app (`ScriptRunner`), because `NSAppleScript` must stay on one thread.

## Main pieces

| File | What it does |
|---|---|
| `PresenterModel.swift` | App state: the deck, the show, slide sync (polling), keyboard and clicker keys, timer, slide images, pointer state, the audience overlay |
| `Views.swift`, `Theme.swift` | The presenter and welcome windows; colours, type and button styles |
| `Annotations.swift`, `AudienceLayer.swift` | Pointer tools and effects, and everything drawn over the audience slide |
| `Prompter.swift`, `PrompterView.swift` | The script, speech-to-script matching (`ScriptAligner`, `VoiceTarget`), the prompter views and the detached window |
| `Speech.swift` | One microphone stream into Apple's speech recognizer, shared by the prompter, coach, captions and voice commands |
| `Coach.swift` | Pace, per-slide budgets, the time cue, speech stats and talk reports |
| `Voice.swift` | Voice commands, live captions, note cues |
| `Remote.swift`, `StageTools.swift` | The local web server for the phone remote and polls, QR codes, the Stage tools panel |
| `PowerPointButtonWatcher.swift` | Spots the PowerPoint button's "Opening Bema" dialog through Accessibility, closes it and presents the deck in front |
| `HotKey.swift`, `BemaApp.swift`, `MenuBarPanel.swift` | The ⌃⌥P shortcut, menus, Finder Services and `bema://` links, the menu bar mini |

## Following the voice

1. `SpeechHub` streams the microphone to `SFSpeechRecognizer` (on-device when available) and hands every partial result to the prompter. It restarts the request every ~50 s and after pauses, and passes the deck's unusual words as `contextualStrings`.
2. `ScriptAligner` aligns the last eight heard words with the script around the current position: a scored alignment where matches count, skipped script words and extra spoken words cost a little, and words heard split or joined still match.
3. `VoiceTarget` turns the stream of guesses into a steady target: small backward revisions are ignored, and big jumps need a second agreeing match made after hearing a new word.
4. The displayed position glides toward the target 60 times a second, never drifts backward on its own, and leads by up to 1.5 words while you speak to hide the recognizer's delay.

Pure logic (`ScriptAligner`, `VoiceTarget`, `VoiceCommands.parse`, `NoteCues`, `PollModel`, `HTTPRequest`) is kept apart from AppKit and speech so it can be tested.

## Overlay over the audience slide

A borderless, non-activating `NSPanel` at screen-saver level, click-through, on all Spaces including full-screen ones, framed to the slide's rectangle inside the slideshow window (read on every poll). A plain `NSWindow` from a regular app doesn't appear on the Space another display is showing, which is why it's a panel.

## Writing speaker notes

- `NoteWriter.swift`: the writers. Apple's on-device model (`FoundationModels`), the OpenAI chat API (OpenAI, Ollama, LM Studio) and the Anthropic Messages API, called with plain `URLSession` requests (no SDK dependency). The prompt (`NotePrompt`), request bodies and response parsing are pure and tested. API keys are in the Keychain (`Keychain`).
- What a writer gets about a slide (`SlideBrief`): its number, title and text, the previous and next titles and, for writers that read pictures, a 1280-pixel PNG. Text and picture both come from the slide previews PDF, so PowerPoint files, cloud decks and Keynote work the same.
- `DraftNotes.swift`: drafts per deck in `~/Library/Application Support/Bema/Draft Notes/` (a hash of the deck's path or web address). The model keeps the deck's slides (`deckSlides`) apart from the drafts and shows them merged (`slides`); a draft is used only where the deck has no notes. `NoteWriting.swift` runs the writing, one slide at a time, and **Save to deck** (`writeNotes` on each controller).
- `BemaMCP.swift`: the MCP server for Claude Desktop. While it's allowed, Bema listens on `~/Library/Application Support/Bema/mcp.sock` (owner-only). Claude Desktop starts `Bema --mcp`, a relay between its stdin/stdout and that socket that starts Bema in the background if needed (`MCPBridge`). `MCPHandler` answers JSON-RPC (`initialize`, `tools/list`, `tools/call` with `get_deck`, `get_slide_image`, `set_speaker_notes`) and is tested against a stand-in deck. `ClaudeDesktop` adds Bema to `claude_desktop_config.json`, keeping the other servers.

