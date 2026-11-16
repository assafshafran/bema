# Decisions

Choices made while building Bema, with the reason, so they are not re-argued or quietly undone. Newest first. Add one whenever a choice is made that the code alone would not explain.

## 2026-11-16

- **One Bema at a time; a second copy hands over and quits.** All copies share the bundle ID, and macOS may give a deck or a `bema://` link to a copy that isn't running, starting a second Bema the presenter doesn't see. Rather than relying on which copy macOS registers, the later Bema forwards its files and links to the earliest one running and quits. It can't simply be refused: the second copy is what received the request.

- **Written notes are drafts kept by Bema until "Save to deck"** (chosen by the maintainer). Bema reads notes from the deck and never changed it before; writing straight into someone's deck, possibly a shared one, is a surprise. Drafts are keyed by slide number, so reordering slides in the deck before saving can put a draft on the wrong slide. Notes the presenter edits in Bema are drafts too (marked "Edited", with an undo back to the deck's notes), so editing follows the same rule: the deck changes only with "Save to deck". Writers and Claude only fill slides that have no notes; replacing notes is the presenter's own edit.
- **The subscription route is MCP from Claude's side, not a button that calls Claude.** A Claude or ChatGPT subscription can't be used by another app: MCP lets Claude call Bema's tools, not the other way round. So Bema is an MCP server and its button copies the request and opens Claude. Claude Desktop runs local servers as commands, so Bema's own binary is the command (`--mcp`) and relays to the running app over a Unix socket that only the user can open, instead of a network port. ChatGPT only connects to MCP servers on the internet, so it isn't offered; API keys cover OpenAI.
- **Writers are called with plain HTTP, not SDKs.** There's no official Swift SDK for either API, and a dependency would be another thing that could phone home. Claude's request turns on server-side fallbacks for models that support them, so a refusal on one slide gets a second try.
- **Slide text and pictures come from the preview PDF,** not the deck file, so the writer sees the same for PowerPoint files, cloud decks and Keynote, including text in shapes that aren't placeholders.
- **The on-device model is the default when it's ready.** It's free and nothing leaves the Mac; the others are a choice the person makes, and each says where the slide goes.

- **Bema asks for the audience display at Start, not only in the top bar** (asked for by the maintainer). PowerPoint hides the choice in Set Up Slide Show, and people find out it's wrong when the slides appear on their laptop. The usual display is preselected so Return keeps it one keystroke; asking can be turned off. It's asked only when there's a choice (two or more displays) and only from Bema itself: the phone remote and clickers start on the remembered display, since nobody is at the Mac to answer.
- **When the deck disappears mid-show, Bema stops instead of waiting.** It checks that the app is still running before each status poll (AppleScript to a quit app relaunches it), and ends the show after ten failed polls in a row (about four seconds) rather than staying "presenting" forever. A show ended in PowerPoint leaves a slideshow view whose state can't be read; that counts as "no show", not a failure.

- **Cloud decks are read through PowerPoint, not downloaded.** PowerPoint reports a web address for a deck opened from OneDrive, SharePoint or Teams. Bema could have PowerPoint save a copy to disk and read that, but saving a copy can move PowerPoint's open document to the copy, and downloading it ourselves would need the person's Microsoft sign-in. Reading titles and notes over AppleScript (as for Keynote) keeps the presenter on the cloud copy and sends nothing anywhere. It costs a few seconds per load (about 12 for 57 slides), and previews are re-exported every time because there's no modification date to cache by. Recents stay files only: a web address can't be reopened without PowerPoint already having it open.

- **The repository moved to the `getbema` organization** (asked for by the maintainer), like Didja's `didja-dev`. GitHub redirects the old `assafshafran/bema` links, so 0.1.0's update feed and downloads keep working.

- **The presenter window is hidden from screen sharing by default** (asked for by the maintainer). People share their screen on calls; notes, the timer and the prompter should never show. Turning it off is one switch in Stage tools.
- **Help lives on getbema.dev, not inside the app.** It stays current without an update, can be linked from issues and the troubleshooting answers, and the Help menu opens the right section.

## 2026-11-15

- **The PowerPoint button is an Office add-in installed by Bema itself.** PowerPoint only adds ribbon buttons through add-ins loaded from an https address; getbema.dev serves it. Bema copies the manifest into PowerPoint's add-in folder rather than sending people to an add-in store, so it works without a Microsoft account and stays tied to the app.
- **The button passes a link, not data.** It reads only the deck's location and opens `bema://present?path=…`; if PowerPoint won't open custom links from an add-in, it falls back to the browser, which hands the link to Bema.

- **Automatic updates with Sparkle, checked once a day** (asked for by the maintainer). The only network traffic Bema starts on its own; it sends only the version, and an update installs only with Bema's EdDSA signature. Its own key account (`bema`), separate from Didja's. Development builds have no feed URL so they never replace themselves with a release.
- **The feed lives on getbema.dev, the files on GitHub Releases.** The site is already deployed from the repository; GitHub hosts the DMG under a stable name (`Bema.dmg`), so the site's Download button and the feed always point at the newest release.
- **Universal builds** (Apple silicon and Intel). SwiftPM builds both at no extra cost, and macOS 14 still runs on Intel Macs.

- **The mark is A2, "the reading line"** (chosen by the maintainer on the design canvas). A letter with a dot beside it is a common shape (Booking.com's "B."); the amber line inside the screen-shaped bowl is unique to Bema, says "presenter" and "prompter" at once, and stays one shape at 16 px. Never put it inside a circle or a red disc (Beats, Bitly). The geometry lives in `site/brand/bema-mark.svg`; `BemaMark` and `Scripts/make_icon.swift` draw the same shape.

- **The public repository is `assafshafran/bema`** (it can move to an organization later; GitHub redirects). Like Didja, the private development history moves to a private history repository, and work continues in the public one through the privacy hooks.
- **The bundle ID is `dev.getbema.Bema`.** The earlier ID contained the maintainer's name; the project now has its own domain.
- **The website lives in the repository (`site/`), like didja.dev in Didja's.** It shows generic app icons, never Apple's or Microsoft's.

- **The public repository starts from a single fresh commit.** The private development history has the maintainer's personal email on every commit and early test text that came from a real deck. Publishing a squashed copy (as Didja did) keeps all of that out, instead of rewriting history that has already been pushed.
- **The privacy check reuses Didja's private names list when it's on the maintainer's Mac.** The same person maintains both, so the same people should never appear in either repository. The list is read locally and never copied.
- **Keynote plays in a window, placed and made full screen by Bema.** Keynote's normal full-screen show uses its own presenter display, which would cover Bema. Without Accessibility, Bema falls back to Keynote's normal show.
- **Keynote's black screen is drawn by Bema.** Keynote has no scripting command for it; the overlay already sits over the slide.
- **Google Slides goes through a .pptx download for now.** It has no AppleScript; driving the browser is fragile, and importing needs a Google sign-in setup.
- **The voice prompter never drifts backward on its own.** When recognition stalls, sliding back to the last confirmed word looked like the text jumping up and down. Only a confirmed jump back, a click, a drag or a slide change moves it up.
- **A lead of at most 1.5 words while speaking.** Three words felt too fast; the lead only hides the recognizer's delay.
- **Small backward revisions are ignored, big jumps need confirmation after a new word.** The recognizer keeps revising its last words, and repeats the same partial result several times; a jump confirmed by a repeat isn't evidence.
- **The reading line sits near the top by default.** People speed up when recognition lags and need to see the next sentence.
- **The phone remote and polls live under random secret paths, and the server runs only while one is on.** Anyone on the same Wi-Fi could otherwise drive the show.
- **The detached prompter is excluded from screen sharing by default** (`NSWindow.sharingType = .none`). Verified with macOS's own capture: on screen but absent from a full-display capture.
- **The overlay over the audience slide is a non-activating `NSPanel`.** A plain `NSWindow` from a regular app doesn't show on the Space another display is showing, even with `.canJoinAllSpaces`.
- **Leaving full screen before ending a show.** Closing a full-screen window directly left an empty black Space on that display.
- **Jumping to a slide in PowerPoint steps one slide at a time.** PowerPoint's `go to slide` fails during a slideshow on Mac.
- **The name is Bema** (βῆμα, the speaker's platform in Athens, root of the Hebrew *bimah*). "MacPoint" was considered and dropped: Apple doesn't allow "Mac" in third-party app names.
- **PowerPoint runs the show rather than Bema rendering slides.** Animations, transitions, video and fonts stay exactly as the deck's author made them.
- **The website's Dock uses our own icons, styled like current macOS, not Apple's or Microsoft's app icons.** Their icon artwork is trademarked and copyrighted, and the repository and site are public.
- **Bema opens macOS's Video Effects menu rather than switching effects itself.** Edge Light, Portrait and Studio Light belong to macOS and apps can't turn them on or off; `AVCaptureDevice.showSystemUserInterface(.videoEffects)` is the supported way in.

## The self view is found by its scene id, not a kept reference (2026-11-16)
SwiftUI reuses a `Window` scene's window when it reopens, so a reference saved when the window first appeared and cleared on close stayed empty after a reopen and closing did nothing. Looking the window up by its identifier each time can't go stale, and the toggle decides by whether that window is on screen.

## Hints shown inside the self view, not only as tooltips (2026-11-16)
The self view floats over other apps while you present from them, and macOS often doesn't show tooltips for an app that isn't active. Pointing at a control writes what it does in the view's bottom label instead.

## One microphone choice for everything that listens (2026-11-16)
The prompter, speech coach, captions and voice commands share one microphone stream (`SpeechHub`), so the choice is the hub's, made in the prompter where people look for it. The audio engine is created fresh each time listening starts and the device is set only then, so the microphone still opens only while a listening feature is on.
