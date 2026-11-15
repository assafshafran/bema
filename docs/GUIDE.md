# Bema guide

A native macOS presenter for **PowerPoint and Keynote** decks, built to replace PowerPoint for Mac's full-screen, non-resizable presenter view.

*Bema* (βῆμα) was the raised platform in ancient Athens where speakers addressed the assembly. It's also the root of the Hebrew *bimah* (בימה), a stage.

PowerPoint still runs the slideshow on the audience display, so animations, transitions and video keep working. Bema drives it through AppleScript and gives you your own presenter window that you can resize, move and put on any display.

## The PowerPoint button
**File → Add Bema Button to PowerPoint…** adds a **Present with Bema** button, with Bema's mark, to PowerPoint's **Home** tab. Quit and reopen PowerPoint to see it. Clicking it hands the open deck to Bema (the same as ⌃⌥P). **File → Remove Bema Button from PowerPoint** takes it away again.

It's a small Office add-in served from `https://getbema.dev/office/` (`site/office/` in this repository). Its manifest goes in PowerPoint's add-in folder, `~/Library/Containers/com.microsoft.Powerpoint/Data/Documents/wef/`, which you can also do by hand: download `https://getbema.dev/office/manifest.xml` into that folder. The button reads only the deck's location and opens a `bema://` link; nothing is sent anywhere.

## Keynote
Open a `.key` file (Finder → Open With → Bema, drag it in, ⌘O, or ⌃⌥P with the deck in front in Keynote) and everything works the same: presenter window, prompter, pointer tools, coach, phone remote.
- Slides, titles, skipped slides and presenter notes are read through Keynote. Previews come from Keynote's PDF export.
- The show plays in a Keynote window (**Play → Play Slideshow in Window**). Bema places it on the audience display and makes it full screen, so Keynote's own presenter display never covers Bema. This needs Accessibility. Without it, Keynote plays its normal full-screen show on the display chosen in Keynote's settings.
- Jumping to a slide uses Keynote's slide switcher.
- Keynote can't black out the screen by script, so Bema draws the black or white screen on its overlay.
- Google Slides: use File → Download → Microsoft PowerPoint (.pptx), then present that file with Bema.

## Phase 1: presenter window (working)
- **Your own presenter window:** current and next slide, speaker notes in an adjustable font size (right-aligned for Hebrew and Arabic), a slide strip to jump around, a timer and a clock. You can resize it, move it and keep it on top.
- **Audience display picker:** the slideshow opens full screen on the display you choose. With only one display, it opens in a window for rehearsal.
- **Follows PowerPoint:** if you click on the slideshow itself, the presenter window keeps up.
- **Laser pointer, pen and highlighter:** pick a tool in the toolbar (or press **L**, **P**, **H**) and point or draw on the current slide in the presenter window. It appears in the same spot on the audience display, on a transparent, click-through layer over PowerPoint's slideshow. **E** clears drawings, and they also clear when the slide changes.
- **Keyboard and clicker:** → ↓ space Page Down Return = next · ← ↑ Page Up = previous · Home / End · **B** or **.** = black screen · **W** or **,** = white screen · **L / P / H** = laser / pen / highlighter · **E** = clear drawings · **Esc** = put the pointer tool away, or end the show · **⌘↩** = start · **⌘+ / ⌘−** = notes size.
- **Reconnects:** if Bema is restarted while the deck's slideshow is running, it picks the show back up.
- **Rehearse without presenting:** before you start the show, the arrows step through slides and notes locally.
- **Present the deck open in PowerPoint:** press **⌃⌥P** from anywhere (including inside PowerPoint), use **File → Present Deck Open in PowerPoint** (⌘⇧P) or the Dock icon's menu, or click **Present** on the welcome screen's "Open in PowerPoint" card.
- **Links:** `bema://present` (the deck open in PowerPoint), `bema://present?path=/full/path/deck.pptx`, `bema://prompter[?place=camera]`. Handy for Shortcuts, Stream Deck or scripts.
- **Opening a deck:**
  - Finder → right-click a `.pptx` → **Open With → Bema**
  - Finder → right-click → **Quick Actions / Services → Present with Bema**
  - Drag a deck onto the window or the Dock icon
  - **File → Open** (⌘O) or **Open Recent**

## Design
A dark "backstage" theme that's easy on the eyes in a dim room, with one amber accent for live state and red only for "live" and the laser.
- **Welcome:** drop zone, recent decks and a *Before you present* checklist that shows PowerPoint, the audience display and Accessibility status as they change.
- **Presenter:** a top bar with Start/End, a LIVE badge, which display the slides are on, the slide counter, pointer tools, black screen, a timer against a planned talk length (click "of 20:00" to change it) and the clock. Current and next slide sit on the left, large notes on the right with the next slide's first line underneath, and a filmstrip runs along the bottom.
- Colors and button styles are in `Sources/Bema/Theme.swift`. The icon is drawn by `Scripts/make_icon.swift` (`swift Scripts/make_icon.swift . && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns`).

## Stage tools
**Pointer effects** (toolbar, or keys while presenting). They show on a transparent, click-through layer over the audience slide:
- **Laser (L)** in five styles from the ✦ menu: red dot, pointing hand, magic wand with sparkles, comet trail, paper plane.
- **Spotlight (S):** dims the slide except a soft circle around your pointer. **Magnifier (M):** zooms into whatever you point at.
- **Pen (P), highlighter (H), stamps (T):** ✓ ✗ ★ ! circle WOW. Click ripples show remote viewers where you clicked. **E** clears drawings and stamps; they also clear when the slide changes.
- **Reactions:** **1** confetti, **2** applause, **3** hearts, across the audience screen.

**Coaching**
- **Pace:** the timer says *On pace*, *1:20 behind* or *0:45 ahead*. Each slide gets a time budget (the planned talk length shared out by how much is in its notes, or your rehearsal timings), shown on the slide header and in the filmstrip.
- **Cue a minute before time is up:** the timer pulses and the trackpad taps; an optional soft sound.
- **Speech coach:** live words per minute and a filler-word count ("um", "like", "you know", "כאילו", "בעצם"…).
- **Rehearsal mode:** when the show ends, a report shows total time against plan, time per slide against its budget, speaking speed and filler words. **Use these timings as slide budgets** makes your rehearsal the plan. **Slideshow → Show Last Talk Report** (⇧⌘R).

**Voice** (on-device recognition where your language supports it):
- **Voice commands:** "next slide", "go back", "go to slide 5", "go to pricing" (matches a slide title), "black screen", and the Hebrew equivalents.
- **Live captions** along the bottom of the audience slide.
- **Note cues:** write `**bold**`, `[pause]`, `[smile]`, `[slow]` or `[look up]` in your PowerPoint notes. They show as highlights and chips in the notes and the prompter, and are never matched against your speech.

**Phone remote and live poll** (Stage tools button ⚙ in the top bar). These are served from your Mac over the local Wi-Fi:
- **Phone remote:** scan the QR code to get next/back, black screen, the timer, your notes, a slide preview, the prompter and confetti on your phone. The link holds a random secret, so others on the network can't use it.
- **Live poll:** type a question and answers, then show it on the audience screen. People scan its QR code to vote (one vote per phone, changeable), and live results appear over the slide.
- Phones must be on the same network. Some office or guest Wi-Fi networks block phone-to-laptop traffic.

**Camera bubble:** a round, mirrored webcam view in a corner of the audience slide, for recorded or hybrid talks.

**Themes and menu bar:** View → Theme: *Backstage* (dark), *Daylight* (bright rooms) or *High contrast*. A small Bema in the menu bar shows the deck, timer, pace and the main controls.

## Phase 2: prompter (working)
Open the **Prompter** tab next to Notes. Your speaker notes become one continuous script across all visible slides.
- **Voice:** listens through the microphone and scrolls as you speak, matching what it hears to your script (it tolerates misheard and skipped words, and recovers if you jump ahead). Recognition runs on the Mac when the language supports it; otherwise Bema says it's using Apple's servers. Language is detected from the notes (English and Hebrew tested) or chosen from the menu.
- **Auto:** scrolls at a set speed in words per minute.
- **Manual:** scroll with the mouse wheel or trackpad, drag the script, or click any word to jump there. All three work in every mode; Voice and Auto carry on from where you leave it.
- **Follow slides** (stack icon): when the script reaches the next slide's notes, the slideshow moves too. When you change slides with the clicker, the script jumps to that slide.
- **Mirror** for teleprompter glass, and A−/A+ for size.
- **Detach** (↗ button, or `bema://prompter`): a separate prompter window that
  - floats above other windows (pin),
  - is **hidden from screen sharing, recordings and screenshots** (eye; on by default, using macOS's window sharing setting),
  - snaps to the top centre of the screen under the camera (camera button, or `bema://prompter?place=camera`), with the reading line near the top so your eyes stay close to the lens,
  - collapses its controls to a thin bar (^), and moves by dragging that bar.
- **Start / Pause Prompter:** ⌥⌘P.

The presenter window can be hidden from screen sharing too: **Slideshow → Hide Presenter Window from Screen Sharing**.

## Build and install
Requirements: macOS 14 or later, Microsoft PowerPoint, Xcode (or the Xcode command line tools with Swift 6).

```bash
./Scripts/build_app.sh --install
```

This builds `build/Bema.app`, copies it to `~/Applications` and registers it with Finder. You can also open `Package.swift` in Xcode.

### Tests
```bash
swift test
```
Covers speech-to-script matching (English, Hebrew, misheard and skipped words), voice-command parsing and title matching, note cues, poll voting, the phone-remote web server (including that a wrong secret is refused), and renders pointer effects, a talk report and a right-to-left script to images in `$TMPDIR`.

### Permissions (first run)
- **Automation → Microsoft PowerPoint:** macOS asks the first time a deck is opened. Required.
- **Microphone and Speech Recognition:** asked the first time anything listens (Voice prompter, speech coach, captions, voice commands).
- **Camera:** asked the first time you turn on the camera bubble.
- **Incoming connections / Local Network:** macOS may ask the first time you turn on the phone remote or a poll.
- **Accessibility:** asked the first time you present on a second display. It lets Bema switch PowerPoint's slideshow window to true full screen on that display. Without it, the slides still show, but with a title bar.

`build_app.sh` signs with your Developer ID or Apple Development certificate when one is installed, so these permissions stick across rebuilds. With an ad-hoc signature, macOS forgets them after each rebuild. If Bema is listed under Accessibility but the full-screen hint still shows, that entry belongs to an older build: remove it with **–** and allow it again.

### Finder Quick Action
If **Present with Bema** doesn't show up when you right-click, turn it on in **System Settings → Keyboard → Keyboard Shortcuts → Services → Files and Folders**.

## How it works
| Piece | File |
|---|---|
| Reads slide titles and speaker notes straight from the `.pptx` XML | `Sources/Bema/PPTXReader.swift` |
| Opens the deck, exports previews (PDF), runs and steps the slideshow through AppleScript | `Sources/Bema/PowerPointController.swift` |
| App state, slideshow sync (polls PowerPoint about 2.5 times a second), keyboard handling | `Sources/Bema/PresenterModel.swift` |
| SwiftUI windows | `Sources/Bema/Views.swift` |
| Prompter: script, speech-to-script matching, microphone and speech recognition | `Sources/Bema/Prompter.swift` |
| Prompter views, detached window, hiding from screen sharing | `Sources/Bema/PrompterView.swift` |
| System-wide shortcut | `Sources/Bema/HotKey.swift` |
| Pointer effects, stamps, ripples, reactions | `Sources/Bema/Annotations.swift` |
| What's drawn on the audience screen (camera bubble, poll, captions) | `Sources/Bema/AudienceLayer.swift` |
| Shared microphone and speech recognition | `Sources/Bema/Speech.swift` |
| Pace, budgets, cues, rehearsal reports | `Sources/Bema/Coach.swift` |
| Voice commands, captions, note cues | `Sources/Bema/Voice.swift` |
| Phone remote, live poll, local web server, QR codes | `Sources/Bema/Remote.swift` |
| Stage tools panel and menu bar mini | `Sources/Bema/StageTools.swift`, `Sources/Bema/MenuBarPanel.swift` |
| Colors, type, button styles and the Bema mark | `Sources/Bema/Theme.swift` |
| Laser pointer, pen, highlighter and the overlay over the audience slide | `Sources/Bema/Annotations.swift` |
| App entry point, Finder Open With and Services | `Sources/Bema/BemaApp.swift` |

Notes on PowerPoint's AppleScript support:
- PowerPoint's `go to slide` command fails during a slideshow on Mac, so jumping to a slide steps there one move at a time.
- The slideshow runs as a "window" show type, which Bema then places on the audience display and makes full screen. PowerPoint's own presenter view is never used.
- When the show ends, Bema takes the slideshow out of full screen before closing it. Closing a full-screen window directly can leave an empty, black Space behind on that display.
- The pointer overlay is a non-activating `NSPanel`. A plain `NSWindow` from a regular app doesn't appear on the Space another display is showing, even with `.canJoinAllSpaces`.
- Slide previews are cached in `~/Library/Caches/Bema`, keyed by file path, modification date and size.

Debug helper: `Bema.app/Contents/MacOS/Bema --dump-notes deck.pptx` prints every slide's title and notes.

## Sample deck
`Samples/Sample.pptx` is generated by `Scripts/make_sample_deck.py` (needs `pip install python-pptx`).
