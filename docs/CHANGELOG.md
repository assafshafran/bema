# Changelog

What was built, newest first. The reasons behind choices are in [DECISIONS.md](DECISIONS.md); how it works is in [ARCHITECTURE.md](ARCHITECTURE.md); what's next is in [ROADMAP.md](ROADMAP.md).

Each entry says what changed and, where it applies, what was **not verified**.

## 2026-11-15

### First release and automatic updates
- `Scripts/release.sh`: a universal build signed with Developer ID and the hardened runtime, notarised and stapled, in a DMG; the update signed with Sparkle and added to `site/appcast.xml`; `--publish` creates the GitHub release and deploys the site.
- Sparkle checks for updates once a day; **Check for Updates…** and **Check for Updates Automatically** are in the Bema menu. Development builds never update themselves.
- The homepage has no placeholders left: the two missing images are illustrations with honest captions, the copy covers Keynote, and Download fetches the DMG.

### The A2 mark in the app
- The app icon, the mark on the welcome and loading screens and the menu bar panel now use A2, the logo chosen for the website: a lowercase b whose bowl is a screen, with the amber reading line inside. The README shows it too.

### Website deploys leave out Wrangler's folder
- `site/.assetsignore` now excludes `.wrangler/`. Earlier deploys had published Wrangler's local account cache file with the site; getbema.dev was redeployed without it and the file now returns 404.

### Ready for a public repository
- The app's bundle ID is now `dev.getbema.Bema` (from getbema.dev). macOS asks for Bema's permissions again once, and its settings start fresh.
- Links point at the public repository, `assafshafran/bema`.
- The website (`site/`, getbema.dev) is in the repository: generic Dock icons instead of other companies' app icons, real links, and Cloudflare's local cache left out.
- MIT license, README for visitors, the full feature guide in `docs/GUIDE.md`, architecture, roadmap, decisions, contributing and security docs, issue templates.
- A privacy check (`Scripts/privacy_check.py`) in git hooks and CI blocks private names, real email addresses, phone numbers, screenshots, database files and secrets (gitleaks).
- CI builds and runs the tests on every push.
- Tests use made-up text only.
- Secrets scan over the full history: gitleaks and trufflehog found nothing. Not verified: the CI workflows on GitHub.

### Keynote
- `.key` decks: slides, skipped slides and presenter notes read through Keynote, previews from Keynote's PDF export, the show in a Keynote window placed full screen on the audience display, jumps through the slide switcher, black and white screen drawn by Bema. Open With, Present with Bema, ⌃⌥P and the welcome card work with Keynote. **Not verified with a live Keynote show yet.**

### Prompter
- Smarter matching: a scored alignment that tolerates skipped and extra words, and words heard split or joined; the deck's unusual words are given to the recognizer as hints.
- Smooth following: a steady target, a 60 fps glide, a small lead while you speak, no drifting backward.
- The reading line sits near the top by default, with a setting; scroll with the mouse or trackpad in every mode; short labels under the prompter's icons.

### Stage tools
- Pointer effects (laser styles, spotlight, magnifier, stamps, ripples, reactions), coaching (pace, per-slide budgets, time cue, words per minute, filler words, rehearsal reports), voice commands, live captions, note cues, phone remote and live poll over local Wi-Fi, camera bubble, Daylight and high-contrast themes, a menu bar mini. Not verified on a real phone, webcam or projector.

### Voice prompter and detached prompter
- Notes as a script that follows your voice, auto-scrolls or is moved by hand; a detached window that floats under the camera and is excluded from screen sharing; present the deck open in PowerPoint with ⌃⌥P; `bema://` links.

### Bema
- Renamed from DeckPresenter; dark "backstage" design; app icon.

### First version
- A resizable presenter window for PowerPoint on Mac: current and next slide, notes, timer, filmstrip, the show full screen on a chosen display, laser pointer, pen and highlighter, Finder Open With and Services.
