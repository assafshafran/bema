# Changelog

What was built, newest first. The reasons behind choices are in [DECISIONS.md](DECISIONS.md); how it works is in [ARCHITECTURE.md](ARCHITECTURE.md); what's next is in [ROADMAP.md](ROADMAP.md).

Each entry says what changed and, where it applies, what was **not verified**.

## 2026-11-16

### Present decks from OneDrive, SharePoint and Teams
- A deck PowerPoint opened from OneDrive, SharePoint or Teams can now be presented: ⌃⌥P, the welcome screen's **Present**, the Dock menu and `bema://present` all find it. Before, Bema said the deck in front "isn't a saved file on this Mac", because PowerPoint reports a web address for these decks and Bema read notes from the file.
- For such a deck Bema reads titles, notes and hidden slides through PowerPoint, and exports the slide previews each time it loads it (there's no modification date to tell when it changed). Saved slide timings and talk reports are kept under the deck's web address. Cloud decks aren't added to Open Recent.
- Checked live with a 57-slide deck PowerPoint had open from the web: notes, titles and previews loaded, and the deck stayed on its web copy after the preview export.
- Not verified: running the slideshow of a cloud deck (it uses the same commands as a local deck, by presentation name), a personal OneDrive deck, decks shared in a Teams chat, and `bema://present?url=https://…` from the PowerPoint add-in.

### Self view that closes every time, camera and microphone choice, a bigger current slide (Bema 0.1.3)
- The self view's X, the toolbar button, the menu bar and ⌥⌘V now close it every time. Bema kept a reference to the window from its first opening and dropped it on close; SwiftUI reuses the window when it reopens, so the reference stayed empty and closing did nothing. Bema now finds the window by its scene each time and decides open or close by whether it's on screen. Turning the camera on and off quickly no longer leaves it in the wrong state (start and stop run in order).
- The self view's hover controls sit on a dark bar with an outline, so they stay readable over a bright picture (Edge Light), and pointing at one says what it does at the bottom of the view. In circle mode the round mask no longer cuts them off (it hid the effects button). The effects button is now a sun, **Light**, in the self view, the top bar and Stage tools.
- Choose the camera from the self view (camera menu) or Stage tools; the bubble on the slides uses the same camera.
- Choose the microphone from the prompter's level meter; it applies to everything that listens.
- Drag the handle under the current slide to make it bigger (double-click resets); the size is remembered.
- Not verified: switching cameras and microphones with real devices (the choice logic is tested; the AVFoundation and Core Audio switching isn't), the hover hints and contrast over Edge Light, and the resize handle in the live window.

### Self view reopens; a control for macOS's video effects (Bema 0.1.2)
- Closing the self view now always turns the camera off and lets it open again. Before, closing it could leave Bema thinking it was still open: the camera kept running and the Self view button did nothing. Bema now watches the window itself close, and the button checks the window, not only its own flag. The self view also opens when Bema's main window is closed (menu bar, ⌥⌘V, `bema://selfview`).
- **Effects** in the top bar (while the camera is on), in the self view's hover controls and in Stage tools opens macOS's Video Effects menu, where Edge Light, Portrait and Studio Light are turned on or off.
- Not verified: the fix live (it's a window-closing timing issue), and the Video Effects menu opening from Bema.
- `Scripts/release.sh` uploads for notarisation and then checks the submission every 30 seconds (up to two hours), retrying a failed upload, and `NOTARY_ID=<id>` resumes a release from the DMG already uploaded. A single long wait failed twice when the connection dropped while Apple was slow.

### A designed sample deck
- `Samples/Sample.pptx` is now the dark six-slide talk from the website ("The slide is the easy part"), with notes written to be read aloud, instead of plain white title slides. `Scripts/make_sample_deck.py` builds it; the separate website copy of the generator is gone. Not verified: the deck in Keynote.

### Interactive demos on getbema.dev
- The pointer tools section is now a live demo: the same toolbar as Bema (laser, spotlight, magnifier, pen, highlighter, stamps, confetti, clear, black screen) drawing on the demo slide, with the same keys while it's on screen.
- The detached prompter section shows your screen during a call (Bema's presenter window, the prompter under the camera, your self view and the people on the call) and a toggle to **What the call sees**: just the slide, your camera bubble and the laser pointer. The prompter highlights the script word by word. Plain JavaScript, no dependencies; animation stops for reduced motion.
- The hero's Dock is redrawn in current macOS style (rounded tiles with gradients and fuller glyphs). The icons are still our own drawings, not Apple's or Microsoft's artwork.
- A square avatar for the GitHub organization (`site/brand/bema-avatar.png`, from `Scripts/make_avatar.swift`).
- Not verified: touch drawing on a real phone.

### Moved to github.com/getbema/bema
- Every link (README, security policy, issue templates, website, help, release script, update feed, Help menu) points at the organization.

### Help, camera controls in the top bar, presenter window hidden from sharing
- A Help page on getbema.dev (getting started, every feature, troubleshooting) and a Help menu in Bema that opens it, plus Report a Problem and What's New.
- **Self view** and **On slides** camera buttons in the top bar and on the welcome screen.
- The presenter window is hidden from screen sharing by default, so a screen share on a call shows the slides, not the notes. It can be turned off in Stage tools.

### Self view
- A floating, mirrored camera window that only you see (excluded from screen sharing: a direct capture of it is refused), round or rectangular, movable under the camera. It shares the camera with the camera bubble. Not verified: the picture itself (it can't be captured by design) and inside Zoom, Teams or Meet shares.

## 2026-11-15

### Menu bar app and Open at Login
- The menu bar icon is the A2 mark (a template image, so it matches light and dark menu bars). Bema keeps running in the menu bar after its window closes. The menu adds Open at login, the PowerPoint button, Check for updates and Quit. **Open Bema at Login** uses macOS's login items. Not verified: the icon in the live menu bar (on this macOS, menu bar items aren't listed per app) and Open at Login across a restart.

### A Present with Bema button in PowerPoint
- An Office add-in (`site/office/`, served from getbema.dev) adds **Present with Bema** to PowerPoint's Home tab; clicking it opens the deck in Bema through a `bema://` link (or, if PowerPoint won't open the link itself, through the browser). Installed and removed from Bema's File menu. Ribbon icons in the A2 mark (`Scripts/make_office_icons.swift`). **Not verified yet: the button in a live PowerPoint**, and whether PowerPoint for Mac opens the link directly.

### Share cards
- `site/brand/bema-social.png` (1280×640, drawn by `Scripts/make_social.swift`) is the GitHub social preview and getbema.dev's share card (Open Graph and X tags on the home and docs pages), plus an iPhone home-screen icon. Not verified: how each app (Slack, X, LinkedIn, iMessage) renders the card.

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
