// "Everything in Bema" on the home page: every feature as a card, filtered by group or search, and a
// side panel with the detail that slides in without taking you away from where you were on the page.
// Keep this list in step with docs/GUIDE.md: every feature there should have a card here.
(function () {
  var GROUPS = [
    { id: "window", name: "Presenter window", icon: '<rect x="3" y="5" width="18" height="13" rx="2"/><path d="M3 9h18M12 9v9"/>' },
    { id: "start", name: "Starting a show", icon: '<path d="M8 5l11 7-11 7z"/>' },
    { id: "notes", name: "Notes and prompter", icon: '<path d="M5 4h14v16H5z"/><path d="M8 9h8M8 13h8M8 17h5"/>' },
    { id: "slide", name: "On the slide", icon: '<circle cx="12" cy="12" r="8"/><circle cx="12" cy="12" r="3"/>' },
    { id: "coach", name: "Coaching", icon: '<circle cx="12" cy="13" r="7"/><path d="M12 13V9M10 3h4"/>' },
    { id: "voice", name: "Voice", icon: '<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11a6.5 6.5 0 0 0 13 0M12 17.5V21"/>' },
    { id: "stage", name: "Phone, camera and polls", icon: '<rect x="7" y="2.5" width="10" height="19" rx="2.5"/><path d="M11 18.5h2"/>' },
    { id: "trust", name: "Privacy and updates", icon: '<path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6z"/>' }
  ];

  // body: short paragraphs and lists. keys: shortcuts shown as keycaps. help: a section of /help.
  var F = [
    // Presenter window
    { id: "resizable", g: "window", t: "A window you can resize and move", s: "Put it on any display, any size, next to anything.",
      b: "<p>PowerPoint for Mac locks its presenter view to full screen. Bema's presenter window is a normal Mac window: resize it, move it to the laptop while the slides play on the projector, or put it beside your camera on a call.</p><ul><li><b>Keep on top</b> keeps it above your call app.</li><li>Closing the window doesn't stop Bema: it stays in the menu bar so shortcuts and the PowerPoint button still find it.</li></ul>", help: "presenting" },
    { id: "current-next", g: "window", t: "This slide and the next", s: "The current slide large, the next one beneath with its first line of notes.",
      b: "<p>The current slide fills the left column; the next slide sits under it with the first line of its notes, so the segue is never a surprise.</p><ul><li>Drag the handle under the current slide to make it bigger or smaller; double-click to reset. The size is remembered.</li><li>Drag the divider beside the notes to give them more room.</li></ul>" },
    { id: "notes", g: "window", t: "Notes you can read", s: "Large type you size yourself. Hebrew and Arabic align right.",
      b: "<p>Your speaker notes in large type on the right, with the next slide's first line underneath.</p><ul><li>Bigger or smaller with ⌘+ and ⌘−, or A− / A+ in the panel.</li><li>Notes in Hebrew or Arabic are right-aligned automatically.</li><li>Cues you write in the notes (<code>**bold**</code>, <code>[pause]</code>, <code>[smile]</code>) show as highlights and chips.</li></ul>", keys: ["⌘+", "⌘−"] },
    { id: "timer", g: "window", t: "A timer against your plan", s: "Elapsed time against a planned length, and the clock.",
      b: "<p>The timer counts against your planned talk length: click “of 20:00” to change it. The clock sits beside it. The timer starts with the show and stops when it ends, including when you end the show in PowerPoint.</p><p>Start or pause it and reset it from the Slideshow menu.</p>" },
    { id: "filmstrip", g: "window", t: "A filmstrip to jump around", s: "Every slide along the bottom. Click one to go there.",
      b: "<p>Every slide runs along the bottom with its number and time budget. Click one to go there, during the show or while you rehearse. Next and back skip hidden slides.</p>" },
    { id: "rehearse", g: "window", t: "Rehearse without presenting", s: "Step through slides and notes before the show starts.",
      b: "<p>Before you start the slideshow, the arrow keys, space and the filmstrip step through your slides and notes inside Bema only. Nothing moves in PowerPoint or Keynote until you start.</p>", keys: ["←", "→", "Space"] },
    { id: "hide-share", g: "window", t: "Hidden from screen sharing", s: "Your presenter window, prompter and self view stay out of every share.",
      b: "<p>Bema uses macOS's own window-sharing setting, so its presenter window, detached prompter and self view don't appear in screen shares, recordings or screenshots. On by default; turn it off in Stage tools or <b>Slideshow → Hide Presenter Window from Screen Sharing</b>.</p><p>Share the slideshow's screen or window as usual: that's what the call sees.</p>", help: "sharing" },
    { id: "themes", g: "window", t: "Themes for any room", s: "Backstage (dark), Daylight and High contrast.",
      b: "<p><b>View → Theme</b>: <b>Backstage</b>, dark and easy on the eyes in a dim room; <b>Daylight</b> for bright rooms; <b>High contrast</b> for the hardest light. One amber accent marks what's live.</p>" },
    { id: "menubar", g: "window", t: "Bema in the menu bar", s: "The deck, timer, pace and the main controls, one click away.",
      b: "<p>A small Bema mark in the menu bar shows the deck, the timer and your pace, with next, back and Start or End. Bema is in the Dock only while its window is open; close the window and it's just this icon, with <b>Show Bema window</b> at the top of its menu. It also opens the detached prompter, adds the PowerPoint button, checks for updates and turns <b>Open at login</b> on or off.</p><p>Turn the icon off from <b>View → Show Bema in the Menu Bar</b>; Bema then quits when its window closes.</p>" },

    // Starting a show
    { id: "open-deck", g: "start", t: "Open a deck your way", s: "Finder, drag and drop, ⌘O, Open Recent or a Quick Action.",
      b: "<ul><li>Finder: right-click a <code>.pptx</code> or <code>.key</code> → <b>Open With → Bema</b>, or <b>Quick Actions → Present with Bema</b>.</li><li>Drag a deck onto the window or the Dock icon.</li><li><b>File → Open</b> (⌘O) or <b>Open Recent</b>.</li></ul><p>Bema reads the titles and notes, and asks PowerPoint or Keynote for slide previews. It doesn't change your deck unless you save notes into it.</p>", keys: ["⌘O"], help: "start" },
    { id: "present-open", g: "start", t: "Present what's open, from anywhere", s: "⌃⌥P hands the deck in PowerPoint or Keynote to Bema.",
      b: "<p>Press ⌃⌥P anywhere, even inside PowerPoint, and Bema loads the deck in front. The same is in <b>File → Present Deck Open in PowerPoint or Keynote</b> (⌘⇧P), the Dock icon's menu and the welcome screen's <b>Present</b> card.</p>", keys: ["⌃⌥P", "⌘⇧P"] },
    { id: "ppt-button", g: "start", t: "A button in PowerPoint", s: "Present with Bema, on PowerPoint's Home tab.",
      b: "<p><b>File → Add Bema Button to PowerPoint…</b> adds a <b>Present with Bema</b> button to PowerPoint's Home tab. Quit and reopen PowerPoint to see it. It hands the open deck to Bema, sending nothing anywhere: it only passes the deck's location to Bema on your Mac.</p>", help: "powerpoint-button" },
    { id: "keynote", g: "start", t: "Keynote too", s: "Everything works the same with .key decks.",
      b: "<p>Open a Keynote deck and you get the same presenter window, prompter, pointer tools, coach and phone remote. Bema reads slides, skipped slides and presenter notes through Keynote and plays the show in a Keynote window it makes full screen, so Keynote's own presenter display never covers Bema.</p><p>Google Slides: download it as PowerPoint (.pptx) and present that.</p>" },
    { id: "cloud", g: "start", t: "Decks from OneDrive, SharePoint and Teams", s: "Open it in PowerPoint from the cloud, then present it from Bema.",
      b: "<p>Open the deck in PowerPoint from the web, Teams or PowerPoint's Open dialog, then press ⌃⌥P. Bema reads the notes through PowerPoint, since there's no file on the Mac, and makes fresh previews each time. The deck stays on its cloud copy.</p>", keys: ["⌃⌥P"] },
    { id: "display", g: "start", t: "Choose where the slides go", s: "Asked at Start, with your usual display ready. Return starts.",
      b: "<p>With two or more displays, <b>Start slideshow</b> asks <i>Where should the slides go?</i>, with a card for each display in its own shape and your usual one already selected. Press Return, click another, or double-click to start there. A warning shows if you pick the display Bema is on.</p><p>Untick <b>Ask every time</b> to skip the question; change the display any time from <b>Slides on</b> in the top bar. With one display, the show opens in a window so you can rehearse.</p>", keys: ["⌘↩"] },
    { id: "fullscreen", g: "start", t: "Full screen on the audience display", s: "PowerPoint or Keynote plays the show, full screen where you chose.",
      b: "<p>Your slideshow app still plays the slides, so animations, transitions and video behave exactly as before. Bema runs it as a window and makes it full screen on the display you chose, so the app's own presenter view never appears. This uses Accessibility permission; without it the slides show with a title bar.</p>", help: "full-screen" },
    { id: "follows", g: "start", t: "Keeps up, and picks the show back up", s: "Click the slideshow and Bema follows. Restart Bema and it reconnects.",
      b: "<ul><li>Click on the slideshow itself and the presenter window keeps up.</li><li>Restart Bema while a show is running and it picks the show back up.</li><li>End the show in PowerPoint (Esc), close the deck or quit PowerPoint and Bema returns to your deck with the timer stopped; Start opens a closed deck again.</li></ul>" },
    { id: "keys", g: "start", t: "Keyboard and clicker", s: "Arrows, space, Page Up and Down, Home and End: any clicker works.",
      b: "<p>→ ↓ space Page Down Return go forward; ← ↑ Page Up go back; Home and End jump to the first and last slide. Clickers send these keys, so they just work. ⌘↩ starts the show and Esc ends it.</p>", keys: ["→", "←", "Home", "End", "⌘↩", "Esc"] },
    { id: "links", g: "start", t: "bema:// links", s: "Start a talk from Shortcuts, Stream Deck or a script.",
      b: "<ul><li><code>bema://present</code>: the deck open in PowerPoint or Keynote.</li><li><code>bema://present?path=/…/deck.pptx</code>: that file.</li><li><code>bema://present?url=https://…</code>: a cloud deck open in PowerPoint.</li><li><code>bema://prompter?place=camera</code> and <code>bema://selfview</code>.</li></ul><p>If you have two copies of Bema, links and decks always reach the one that's open.</p>" },

    // Notes and prompter
    { id: "prompter", g: "notes", t: "A prompter that follows your voice", s: "Your notes as one script that scrolls as you speak.",
      b: "<p>Open the <b>Prompter</b> tab and your notes become one continuous script. Bema listens and keeps your place by matching what it hears to the words, coping with misheard and skipped words and finding you again if you jump ahead.</p><p>English and Hebrew are tested; the language is detected from your notes. Start or pause with ⌥⌘P.</p>", keys: ["⌥⌘P"], help: "prompter" },
    { id: "prompter-modes", g: "notes", t: "Auto and manual scrolling", s: "Rather not be listened to? Scroll at a set pace, or by hand.",
      b: "<p><b>Auto</b> scrolls at a speed you set in words per minute. <b>Manual</b> lets you scroll, drag the script or click any word to jump there. All three work in every mode, and Voice and Auto carry on from where you leave them.</p>" },
    { id: "follow-slides", g: "notes", t: "Slides follow the script", s: "Reach the next slide's notes and the slideshow moves with you.",
      b: "<p>Turn on <b>Follow slides</b> (the stack icon): when the script reaches the next slide's notes, the slideshow advances. Change slides with the clicker and the script jumps to match.</p>" },
    { id: "detached", g: "notes", t: "A prompter under your camera", s: "A small window at the top of the screen, out of the screen share.",
      b: "<p>Press ↗ and the prompter becomes its own window. Snap it to the top centre, right under the camera, with the reading line near the top so your eyes stay close to the lens.</p><ul><li>Hidden from screen sharing, recordings and screenshots.</li><li>Floats above other windows and folds its controls into a thin bar you drag.</li><li>Mirror mode for teleprompter glass.</li></ul>" },
    { id: "cues", g: "notes", t: "Cues in your notes", s: "**bold**, [pause], [smile], [slow], [look up].",
      b: "<p>Write <code>**bold**</code> for words to stress, or <code>[pause]</code>, <code>[smile]</code>, <code>[slow]</code>, <code>[look up]</code> in your notes. They show as highlights and chips in the notes and the prompter, and are never matched against your speech.</p>" },
    { id: "edit-notes", g: "notes", t: "Edit notes in Bema", s: "Change any slide's notes, or type them for a slide that has none.",
      b: "<p>Click the pencil next to a slide's title, or <b>Type notes</b> on a slide with none. ⌘↩ keeps the change, Esc cancels. Your changes are marked <b>Edited</b> and the prompter follows them at once.</p><p><b>Save to deck</b> writes them into PowerPoint's or Keynote's speaker notes and saves; ↶ goes back to the deck's notes.</p>", keys: ["⌘↩", "Esc"], help: "speaker-notes" },
    { id: "write-notes", g: "notes", t: "Write notes for slides that have none", s: "On your Mac, with a local model, an API key or your Claude subscription.",
      b: "<p>On a slide with no notes, <b>Write notes</b> drafts them; <b>All slides without notes</b> does the rest. Drafts stay in Bema for you to edit until you <b>Save to deck</b>, and notes already in your deck are never replaced. Choose the writer in <b>View → Notes Writer Settings…</b>:</p><ul><li><b>On this Mac</b> with Apple Intelligence: free, nothing leaves the Mac.</li><li><b>A local model</b> in Ollama or LM Studio.</li><li><b>Your Claude or OpenAI API key</b>: the slide goes to that company only when you ask.</li><li><b>The Claude app</b> with your subscription: Claude reads the slides from Bema and puts notes back.</li></ul>", help: "speaker-notes" },
    { id: "microphone", g: "notes", t: "Choose the microphone", s: "From the prompter's level meter; everything that listens uses it.",
      b: "<p>Click the prompter's level meter to pick the system default or any connected microphone. The prompter, captions, voice commands and speech coach all use it, and switching while listening carries straight on.</p>" },

    // On the slide
    { id: "laser", g: "slide", t: "Laser pointer, five ways", s: "Red dot, pointing hand, magic wand, comet trail or paper plane.",
      b: "<p>Press L and point on the slide in your presenter window: the laser appears in the same spot on the audience display, on a transparent layer the clicks pass through. Pick a style from the ✦ menu. Try it in the demo further down this page.</p>", keys: ["L"] },
    { id: "spotlight", g: "slide", t: "Spotlight and magnifier", s: "Dim everything but your point, or zoom into it.",
      b: "<p><b>Spotlight</b> (S) dims the slide except a soft circle around your pointer. <b>Magnifier</b> (M) zooms into whatever you point at, for the small print on a chart.</p>", keys: ["S", "M"] },
    { id: "draw", g: "slide", t: "Pen, highlighter and stamps", s: "Draw on the slide, mark it ✓ ✗ ★ ! or circle it.",
      b: "<p>P pen, H highlighter, T stamps (✓ ✗ ★ ! circle WOW). Click ripples show remote viewers where you clicked. E clears everything; drawings also clear when the slide changes.</p>", keys: ["P", "H", "T", "E"] },
    { id: "reactions", g: "slide", t: "Confetti, applause and hearts", s: "A moment of celebration across the audience screen.",
      b: "<p>Press 1 for confetti, 2 for applause and 3 for hearts, over the slide the audience sees. Also on the phone remote.</p>", keys: ["1", "2", "3"] },
    { id: "blank", g: "slide", t: "Black or white screen", s: "Take the audience's eyes off the slide.",
      b: "<p>B or . blacks the screen, W or , whitens it; press again to come back. PowerPoint does it itself; for Keynote, Bema draws it on its overlay.</p>", keys: ["B", "W"] },
    { id: "bubble", g: "slide", t: "Your camera on the slide", s: "A round camera bubble in a corner of the audience slide.",
      b: "<p>Turn on <b>On slides</b> and a round, mirrored view of your camera sits in a corner of the audience slide: for recorded and hybrid talks where people should see you and the slide together. Choose the camera in Stage tools.</p>" },
    { id: "captions", g: "slide", t: "Live captions", s: "What you say, along the bottom of the audience slide.",
      b: "<p>Turn on captions and the last few words you said run along the bottom of the slide, for people at the back of the room or in a second language. Only those few words are kept, never a transcript.</p>" },

    // Coaching
    { id: "pace", g: "coach", t: "On pace, behind or ahead", s: "The timer tells you how you're doing, slide by slide.",
      b: "<p>The timer says <i>On pace</i>, <i>1:20 behind</i> or <i>0:45 ahead</i>. Each slide gets a time budget, shared out by how much is in its notes or taken from your rehearsal, shown on the slide header and in the filmstrip.</p>" },
    { id: "minute-cue", g: "coach", t: "A cue a minute before time", s: "The timer pulses and the trackpad taps.",
      b: "<p>A minute before your planned time is up, the timer pulses and the trackpad gives a tap you feel but nobody hears. A soft sound is optional.</p>" },
    { id: "speech-coach", g: "coach", t: "Words per minute and filler words", s: "Live speaking speed, and a count of “um”, “like”, “you know”.",
      b: "<p>While you talk, Bema shows your words per minute and counts filler words in English and Hebrew (“um”, “like”, “you know”, “כאילו”, “בעצם”…), so you notice before the audience does.</p>" },
    { id: "report", g: "coach", t: "A report after every rehearsal", s: "Time against plan, per slide, with your pace and fillers.",
      b: "<p>When the show ends, a report shows total time against plan, each slide against its budget, speaking speed and filler words. <b>Use these timings as slide budgets</b> makes your rehearsal the plan. Reopen it with ⇧⌘R. Reports hold timings and counts only.</p>", keys: ["⇧⌘R"] },

    // Voice
    { id: "voice-commands", g: "voice", t: "Voice commands", s: "“Next slide”, “go to pricing”, “black screen”, in English or Hebrew.",
      b: "<p>Say “next slide”, “go back”, “go to slide 5”, “go to pricing” (matched against your slide titles) or “black screen”, or the Hebrew equivalents, and Bema does it. Handy when your hands are full or the clicker died.</p>" },
    { id: "on-device", g: "voice", t: "Speech on your Mac", s: "Recognition runs on the Mac when your language allows it.",
      b: "<p>The prompter, captions, voice commands and speech coach use Apple's speech recognition on your Mac when it supports your language offline. When it doesn't, Bema tells you it's using Apple's servers before it listens. The microphone opens only while one of these is on, and audio is never saved.</p>" },

    // Phone, camera and polls
    { id: "remote", g: "stage", t: "Your phone as a remote", s: "Scan a QR code: next, back, notes, timer and preview on your phone.",
      b: "<p>Open <b>Stage tools</b> and scan the QR code. Your phone gets next and back, black screen, the timer, your notes, a slide preview, the prompter and confetti, over your Wi-Fi. The link holds a random secret, so nobody else on the network can drive your talk. Some guest networks block phone-to-laptop traffic.</p>", keys: ["⇧⌘T"], help: "remote" },
    { id: "poll", g: "stage", t: "Live polls", s: "Ask a question; the room votes from their phones; results on the slide.",
      b: "<p>Type a question and answers in Stage tools and show it on the audience screen. People scan its QR code to vote, one changeable vote per phone, and live results appear over the slide. Everything runs on your Mac over the local network.</p>", help: "remote" },
    { id: "self-view", g: "stage", t: "A self view only you see", s: "A small mirror of your camera, out of every share.",
      b: "<p>A small, movable view of your camera that floats above the slideshow and your call, and stays out of screen shares and recordings. Choose the camera (built-in, a webcam or your iPhone), round or rectangle, and snap it under the camera. ⌥⌘V opens and closes it.</p>", keys: ["⌥⌘V"], help: "camera" },
    { id: "effects", g: "stage", t: "Light and video effects", s: "Edge Light, Studio Light and Portrait, one click away.",
      b: "<p>macOS adds its own camera effects to any app using the camera. Bema's <b>Light</b> button (the sun) opens the Video Effects menu, so you can turn on Edge Light, Studio Light or Portrait before you go on.</p>" },
    { id: "devices", g: "stage", t: "Choose the camera", s: "Built-in, webcam or iPhone, for the self view and the bubble.",
      b: "<p>Pick the camera in Stage tools or the self view's camera menu; the camera bubble uses the same one. If it's unplugged, Bema falls back to the system default.</p>" },

    // Privacy and updates
    { id: "private", g: "trust", t: "No account, no analytics", s: "Nothing leaves your Mac unless you turn it on.",
      b: "<p>No account, no cloud service, no analytics. Audio is never saved, transcripts never kept beyond a few caption words, talk reports stay on your Mac. The phone remote's server runs only while it's on. Notes writers send a slide only to the writer you chose, when you ask.</p>" },
    { id: "updates", g: "trust", t: "Signed updates", s: "Checked once a day, installed only with Bema's signature.",
      b: "<p>Once a day Bema checks getbema.dev for a new version, sending only its version number. An update installs only with Bema's signature. Turn automatic checks off in the Bema menu, or check now with <b>Check for Updates…</b>.</p>", help: "updates" },
    { id: "open-source", g: "trust", t: "Free and open source", s: "MIT licence. Read it, build it, change it.",
      b: "<p>Bema is a native SwiftUI app, free under the MIT licence. Every feature here is in the repository, with tests. Releases are signed and notarised by Apple.</p><p><a href=\"https://github.com/getbema/bema\">github.com/getbema/bema</a></p>" }
  ];

  var root = document.getElementById("features");
  if (!root) return;
  var grid = root.querySelector(".fgrid");
  var chips = root.querySelector(".fchips");
  var search = root.querySelector(".fsearch");
  var count = root.querySelector(".fcount");
  var panel = document.getElementById("fpanel");
  var scrim = document.getElementById("fscrim");
  var group = "all";
  var opener = null;
  var openId = null;

  function gOf(id) { for (var i = 0; i < GROUPS.length; i++) if (GROUPS[i].id === id) return GROUPS[i]; }
  function icon(g, cls) {
    return '<svg class="' + cls + '" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">' + gOf(g).icon + "</svg>";
  }
  function text(html) { var d = document.createElement("div"); d.innerHTML = html; return d.textContent.toLowerCase(); }
  function keycaps(keys) {
    return (keys || []).map(function (k) { return "<kbd>" + k + "</kbd>"; }).join(" ");
  }

  // Filter chips: All plus one per group, with counts.
  chips.innerHTML = [{ id: "all", name: "All" }].concat(GROUPS).map(function (g) {
    var n = g.id === "all" ? F.length : F.filter(function (f) { return f.g === g.id; }).length;
    return '<button type="button" class="fchip' + (g.id === "all" ? " on" : "") + '" data-g="' + g.id + '" aria-pressed="' + (g.id === "all") + '">' +
      g.name + ' <span>' + n + "</span></button>";
  }).join("");

  grid.innerHTML = F.map(function (f) {
    f.search = (f.t + " " + f.s + " " + text(f.b) + " " + (f.keys || []).join(" ") + " " + gOf(f.g).name).toLowerCase();
    return '<button type="button" class="fcard" data-id="' + f.id + '" data-g="' + f.g + '" aria-haspopup="dialog">' +
      '<span class="fcard-top">' + icon(f.g, "fic") + '<span class="fgroup">' + gOf(f.g).name + "</span></span>" +
      '<span class="fcard-t">' + f.t + "</span>" +
      '<span class="fcard-s">' + f.s + "</span>" +
      '<span class="fmore" aria-hidden="true">More <svg viewBox="0 0 16 16"><path d="M6 3l5 5-5 5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg></span>' +
      "</button>";
  }).join("");
  var cards = Array.prototype.slice.call(grid.querySelectorAll(".fcard"));

  function visible() {
    return F.filter(function (f) {
      var el = grid.querySelector('[data-id="' + f.id + '"]');
      return el && !el.hidden;
    });
  }

  function apply() {
    var q = (search.value || "").trim().toLowerCase();
    var shown = 0;
    F.forEach(function (f, i) {
      var ok = (group === "all" || f.g === group) && (!q || q.split(/\s+/).every(function (w) { return f.search.indexOf(w) >= 0; }));
      cards[i].hidden = !ok;
      if (ok) shown++;
    });
    count.textContent = shown === F.length ? F.length + " features" : shown + " of " + F.length + " features";
    root.querySelector(".fempty").hidden = shown > 0;
  }

  chips.addEventListener("click", function (e) {
    var b = e.target.closest(".fchip");
    if (!b) return;
    group = b.getAttribute("data-g");
    Array.prototype.forEach.call(chips.children, function (c) {
      var on = c === b;
      c.classList.toggle("on", on);
      c.setAttribute("aria-pressed", on ? "true" : "false");
    });
    apply();
  });
  search.addEventListener("input", apply);

  // The side panel.
  var body = panel.querySelector(".fp-body");
  var prevB = panel.querySelector(".fp-prev"), nextB = panel.querySelector(".fp-next");

  function render(f) {
    var list = visible().length ? visible() : F;
    var i = list.indexOf(f);
    if (i < 0) { list = F; i = F.indexOf(f); }
    var related = F.filter(function (x) { return x.g === f.g && x !== f; });
    body.innerHTML =
      '<p class="fp-group">' + icon(f.g, "fp-ic") + gOf(f.g).name + "</p>" +
      '<h3 class="fp-title" id="fp-title">' + f.t + "</h3>" +
      '<p class="fp-lede">' + f.s + "</p>" +
      (f.keys ? '<p class="fp-keys">' + keycaps(f.keys) + "</p>" : "") +
      '<div class="fp-text">' + f.b + "</div>" +
      (f.help ? '<p class="fp-help"><a href="/help#' + f.help + '">More in Help →</a></p>' : "") +
      (related.length ? '<p class="fp-rel-h">Also in ' + gOf(f.g).name + '</p><div class="fp-rel">' +
        related.map(function (r) { return '<button type="button" data-id="' + r.id + '">' + r.t + "</button>"; }).join("") + "</div>" : "");
    body.scrollTop = 0;
    var prev = list[(i - 1 + list.length) % list.length], next = list[(i + 1) % list.length];
    prevB.setAttribute("data-id", prev.id);
    nextB.setAttribute("data-id", next.id);
    prevB.querySelector("span").textContent = prev.t;
    nextB.querySelector("span").textContent = next.t;
    panel.querySelector(".fp-pos").textContent = (i + 1) + " / " + list.length;
  }

  function byId(id) { for (var i = 0; i < F.length; i++) if (F[i].id === id) return F[i]; }

  function open(id, from) {
    var f = byId(id);
    if (!f) return;
    if (!openId) opener = from || document.activeElement;
    openId = id;
    render(f);
    panel.hidden = false;
    scrim.hidden = false;
    requestAnimationFrame(function () { panel.classList.add("in"); scrim.classList.add("in"); });
    document.documentElement.classList.add("fp-open");
    history.replaceState(null, "", "#feature-" + id);
    panel.querySelector(".fp-close").focus({ preventScroll: true });
  }

  function close() {
    if (!openId) return;
    openId = null;
    panel.classList.remove("in");
    scrim.classList.remove("in");
    document.documentElement.classList.remove("fp-open");
    setTimeout(function () { if (!openId) { panel.hidden = true; scrim.hidden = true; } }, 260);
    history.replaceState(null, "", location.pathname + location.search);
    if (opener && opener.focus) opener.focus({ preventScroll: true });
  }

  grid.addEventListener("click", function (e) {
    var c = e.target.closest(".fcard");
    if (c) open(c.getAttribute("data-id"), c);
  });
  // Anything else on the page can open a feature: <a data-feature="laser">.
  document.addEventListener("click", function (e) {
    var a = e.target.closest("[data-feature]");
    if (!a) return;
    e.preventDefault();
    open(a.getAttribute("data-feature"), a);
  });
  panel.addEventListener("click", function (e) {
    var b = e.target.closest("[data-id]");
    if (b && panel.contains(b)) open(b.getAttribute("data-id"));
  });
  panel.querySelector(".fp-close").addEventListener("click", close);
  scrim.addEventListener("click", close);
  document.addEventListener("keydown", function (e) {
    if (!openId) return;
    if (e.key === "Escape") { e.preventDefault(); close(); }
    else if ((e.key === "ArrowRight" || e.key === "ArrowLeft") && !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) {
      e.preventDefault();
      (e.key === "ArrowRight" ? nextB : prevB).click();
    } else if (e.key === "Tab") {
      // Keep focus in the panel while it's open.
      var items = panel.querySelectorAll("button, a[href]");
      var first = items[0], last = items[items.length - 1];
      if (e.shiftKey && document.activeElement === first) { e.preventDefault(); last.focus(); }
      else if (!e.shiftKey && document.activeElement === last) { e.preventDefault(); first.focus(); }
    }
  });

  apply();
  var m = location.hash.match(/^#feature-([a-z-]+)$/);
  if (m && byId(m[1])) {
    root.scrollIntoView();
    open(m[1]);
  }
  window.BemaFeatures = { count: F.length, ids: F.map(function (f) { return f.id; }) };
})();
