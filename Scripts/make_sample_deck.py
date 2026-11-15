"""Generate Samples/Sample.pptx: a 6-slide deck with speaker notes, for testing Bema.

Usage: python3 -m pip install python-pptx && python3 Scripts/make_sample_deck.py
"""
from pathlib import Path
from pptx import Presentation
from pptx.util import Pt

SLIDES = [
    ("Bema sample", "A test deck with speaker notes",
     "Welcome everyone. This is the sample deck used to test Bema.\n"
     "The notes for each slide appear in the presenter window."),
    ("Why a new presenter view", "PowerPoint for Mac locks presenter view to full screen",
     "On a Mac, PowerPoint's presenter view takes over the whole display.\n"
     "You can't resize it, move it or put other windows next to it."),
    ("How it works", "PowerPoint shows the slides; Bema shows everything else",
     "PowerPoint still runs the slideshow, so animations and video keep working.\n"
     "Bema drives it with AppleScript and shows notes in its own window."),
    ("Controls", "Arrow keys, space, Page Up and Page Down, B for black screen",
     "Clickers send Page Up and Page Down, and both work.\n"
     "Press B to black out the audience screen."),
    ("Notes with a long script", "This slide has a lot of notes",
     " ".join(["This paragraph is long so we can check how the notes panel scrolls and wraps."] * 8)),
    ("Thank you", "Questions?",
     "Thank everyone and open the floor for questions."),
]

prs = Presentation()
for title, subtitle, notes in SLIDES:
    slide = prs.slides.add_slide(prs.slide_layouts[1])
    slide.shapes.title.text = title
    body = slide.placeholders[1].text_frame
    body.text = subtitle
    body.paragraphs[0].font.size = Pt(28)
    slide.notes_slide.notes_text_frame.text = notes

out = Path(__file__).resolve().parent.parent / "Samples" / "Sample.pptx"
prs.save(out)
print(out)
