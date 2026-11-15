# Bema

A native macOS presenter for PowerPoint and Keynote decks: the presentation app runs the slideshow on the audience display, Bema gives the presenter their own window, a voice-following prompter, pointer tools, coaching, a phone remote and polls. Read [README.md](README.md) and [docs/GUIDE.md](docs/GUIDE.md) for the product, [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how it works, [docs/ROADMAP.md](docs/ROADMAP.md) for what's planned, [docs/CHANGELOG.md](docs/CHANGELOG.md) for what was built and [docs/DECISIONS.md](docs/DECISIONS.md) for why.

## Layout

- `Sources/Bema/` — the app (SwiftUI, a Swift package). `SlideshowApp.swift` holds the PowerPoint/Keynote interface and the Keynote controller; `PowerPointController.swift` drives PowerPoint; `PresenterModel.swift` is the app state.
- `Tests/BemaTests/` — XCTest: pure logic plus render tests that draw views to `$TMPDIR/bema-*.png`.
- `Resources/` — `Info.plist` and the app icon. `Samples/` — the made-up sample deck. `Scripts/` — build, icon, sample deck and the privacy check.

## Commands

```bash
swift test                                   # tests
./Scripts/build_app.sh --install             # development build (never updates itself), install to ~/Applications
Scripts/release.sh --publish                 # Developer ID, notarised, Sparkle-signed; GitHub release + appcast + site deploy
open ~/Applications/Bema.app Samples/Sample.pptx
python3 -I -m unittest discover -s Scripts -p 'test_*.py'   # the privacy checker's tests
python3 -I Scripts/privacy_check.py tree     # scan everything tracked for personal content
```

## Hard rules

- The presentation app renders what the audience sees; Bema never re-renders slides for them.
- Nothing leaves the Mac unless the person turned it on: no analytics, no accounts, no dependencies that phone home. The one exception, chosen by the maintainer: Sparkle's update check, once a day to https://getbema.dev/appcast.xml (only the app's version), on by default and off from the Bema menu, never in development builds (`Scripts/build_app.sh` removes the feed) or tests; an update installs only with a valid EdDSA signature (`SUPublicEDKey`, key account `bema`). Speech is on-device when the language supports it, and Bema says when it isn't. The local web server (phone remote, polls) runs only while one is on, under random secret paths.
- Never write audio to disk. Transcripts are kept only as the last few caption words; talk reports hold timings and counts only.
- The microphone opens only for a listening feature that is on (`SpeechHub` consumers) and closes when none needs it. Don't touch `AVAudioEngine.inputNode` before then: creating it can trigger the microphone prompt.
- Windows marked hidden from screen sharing (`sharingType = .none`) must stay hidden.

## Personal content (the repository will be public)

- Anything from a screenshot, a deck, notes, a chat or an email you were shown is private input: use it to understand the problem, never copy it. That covers names, company and client names, deck titles and wording, email addresses and phone numbers.
- Tests, sample decks, docs, code comments, commit messages and the CHANGELOG use made-up equivalents with the same shape: "Sam", "Noa", `example.com`, "Acme", made-up Hebrew.
- Never commit a screenshot or a recording. Images come from `Resources/`, `brand/`, `site/` or renders the tests draw from made-up data (`docs/images/`).
- Refer to the maintainer as "the maintainer", not by name.
- The git hooks in `.githooks/` (`git config core.hooksPath .githooks`, once per clone) block a commit or push that adds a private name, a real email address, a phone number, a screenshot or a database, and run gitleaks. If a hook blocks you, change the content; never use `--no-verify`. CI runs the same check without the names.

## Conventions

- Every behaviour change comes with a test. Keep pure logic apart from AppKit, AppleScript, Accessibility and speech so it can be tested (`ScriptAligner`, `VoiceTarget`, `VoiceCommands.parse`, `NoteCues`, `PollModel`, `HTTPRequest`).
- UI changes: run the render tests and look at `$TMPDIR/bema-*.png`; for live checks, capture only Bema's own window (`screencapture -l <window id>`), never the whole screen.
- AppleScript for each app runs on one serial queue (`ScriptRunner`, `PowerPointController.run`). AppleScript variable names must not clash with app terms (`st` is reserved in PowerPoint).
- The app is signed with a stable identity by `Scripts/build_app.sh` so its permissions survive rebuilds. Don't change signing.
- Update README.md and docs/ (feature detail is in docs/GUIDE.md) when behaviour changes. Every change adds an entry to `docs/CHANGELOG.md` (what changed, what was not verified), and every choice the code doesn't explain goes in `docs/DECISIONS.md`. Both in the same commit as the change.
