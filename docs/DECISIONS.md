# Decisions

Choices made while building Bema, with the reason, so they are not re-argued or quietly undone. Newest first. Add one whenever a choice is made that the code alone would not explain.

## 2026-11-16

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
