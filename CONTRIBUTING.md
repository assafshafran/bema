# Contributing

Thanks for helping. Bema is small, so a short issue first is the easiest way to agree on a change before you write it.

## Build and test

You need Xcode 16 or later (or the Swift 6 command line tools), and PowerPoint or Keynote to try a show.

```bash
swift test                        # all tests
./Scripts/build_app.sh --install  # build Bema.app into build/ and copy it to ~/Applications
open ~/Applications/Bema.app Samples/Sample.pptx
```

`Samples/Sample.pptx` is a made-up deck with speaker notes (`Scripts/make_sample_deck.py` regenerates it). The build script signs with your own Developer ID or Apple Development certificate if you have one, otherwise ad hoc. Please don't commit signing changes.

## Keep your own data out

Bema presents your decks and listens to you speak, so test decks, notes and bug reports are tempting places for real content. Don't put it there.

- Turn on the checks once per clone: `git config core.hooksPath .githooks` (needs `brew install gitleaks`). They block a commit or push that adds an email address outside made-up domains, a phone number, a screenshot or a database file, and run gitleaks. If you keep a private names list (see `Scripts/privacy_check.py`), they block those names too; the list stays on your Mac.
- Write tests and sample decks with made-up people and text (`Sam`, `Noa`, `example.com`, `Acme`), keeping the shape of what you saw. Hebrew examples are made-up Hebrew.
- Never commit a screenshot or a recording. Images come from `Resources/`, `brand/`, or renders the tests draw from made-up data (`docs/images/`).

## The rules

These are what people trust Bema with. A change that breaks one won't be merged.

- **The presentation app renders the slides.** Bema never re-renders what the audience sees.
- **Nothing leaves the Mac unless the person turned it on.** No analytics, no accounts, no dependencies that phone home. Speech uses on-device recognition when the language has it, and says clearly when it doesn't. The phone remote and poll server runs only while one of them is on, under a random secret path.
- **Nothing is recorded.** Audio is never written to disk, and transcripts are kept only as the last few words for captions. Talk reports hold timings and counts, not words.
- **Listening only when asked.** The microphone opens only for a listening feature the person turned on, and closes when none needs it.
- **Hidden from sharing means hidden.** A window marked as excluded from screen sharing must stay excluded.

## Every change

- **Comes with a test.** Pure logic is kept apart from AppKit, AppleScript and speech so it can be tested (see `Tests/BemaTests`).
- **Shows UI changes.** The render tests draw views to `$TMPDIR/bema-*.png`; look at them and attach the relevant one to the pull request.
- **Gets a `docs/CHANGELOG.md` entry** (newest first: what changed, and what was not verified).
- **Records its decisions** in `docs/DECISIONS.md` when the code doesn't explain the choice.
- **Updates the docs** (`README.md`, `docs/GUIDE.md`) when behaviour changes.

Keep commits small, with plain messages.
