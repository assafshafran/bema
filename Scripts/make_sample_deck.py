"""Generate Samples/Sample.pptx, the made-up deck for trying and testing Bema (also the deck in the
website's screenshots): "The slide is the easy part", a six-slide talk about AI and presentation
tools, with speaker notes written to be read aloud for the voice prompter.

Usage: python3 -m pip install python-pptx && python3 Scripts/make_sample_deck.py [out.pptx]
"""
import random, sys
from pathlib import Path
from pptx import Presentation
from pptx.util import Inches, Pt
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR

W, H = Inches(13.333), Inches(7.5)
prs = Presentation()
prs.slide_width, prs.slide_height = W, H
blank = prs.slide_layouts[6]
random.seed(11)

INK = RGBColor(0x0A, 0x0C, 0x14)
DEEP = RGBColor(0x12, 0x15, 0x2B)
CREAM = RGBColor(0xF4, 0xF1, 0xEA)
AMBER = RGBColor(0xF5, 0xA5, 0x24)
CYAN = RGBColor(0x3D, 0xD9, 0xE8)
VIOLET = RGBColor(0x7C, 0x5C, 0xFF)
MUTED = RGBColor(0x9A, 0xA1, 0xBD)
DIM = RGBColor(0x2C, 0x31, 0x52)
FONT = "Helvetica Neue"


def bg(slide, color):
    f = slide.background.fill
    f.solid(); f.fore_color.rgb = color


def shape(slide, kind, x, y, w, h, color, line=None, lw=None):
    s = slide.shapes.add_shape(kind, Inches(x), Inches(y), Inches(w), Inches(h))
    if color is None:
        s.fill.background()
    else:
        s.fill.solid(); s.fill.fore_color.rgb = color
    if line is None:
        s.line.fill.background()
    else:
        s.line.color.rgb = line
        if lw: s.line.width = Pt(lw)
    s.shadow.inherit = False
    return s


def line(slide, x1, y1, x2, y2, color, lw=1.5):
    c = slide.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    c.line.color.rgb = color; c.line.width = Pt(lw)
    return c


def text(slide, x, y, w, h, s, size, color, bold=False, align=PP_ALIGN.LEFT, spacing=None):
    tb = slide.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    tf = tb.text_frame; tf.word_wrap = True
    tf.margin_left = tf.margin_right = 0
    for i, ln in enumerate(s.split("\n")):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        if spacing: p.line_spacing = spacing
        r = p.add_run(); r.text = ln
        r.font.size = Pt(size); r.font.bold = bold; r.font.color.rgb = color; r.font.name = FONT
    return tb


def network(slide, x0, y0, w, h, n=16):
    """A loose node graph: dots joined by thin lines."""
    pts = [(x0 + random.uniform(0, w), y0 + random.uniform(0, h)) for _ in range(n)]
    for i, (x, y) in enumerate(pts):
        near = sorted(pts, key=lambda p: (p[0] - x) ** 2 + (p[1] - y) ** 2)[1:3]
        for (a, b) in near:
            line(slide, x, y, a, b, DIM, 1.25)
    for i, (x, y) in enumerate(pts):
        d = random.choice([0.1, 0.14, 0.18, 0.24])
        c = random.choice([MUTED, MUTED, CYAN, VIOLET, AMBER])
        shape(slide, MSO_SHAPE.OVAL, x - d / 2, y - d / 2, d, d, c)


def notes(slide, s):
    slide.notes_slide.notes_text_frame.text = s


# 1 Title
s = prs.slides.add_slide(blank); bg(s, INK)
network(s, 7.6, 0.6, 5.2, 5.6, 18)
shape(s, MSO_SHAPE.OVAL, 9.2, 2.4, 1.6, 1.6, AMBER)
shape(s, MSO_SHAPE.RECTANGLE, 0.8, 1.15, 0.5, 0.08, AMBER)
text(s, 0.8, 0.7, 6, 0.4, "KEYNOTE · THE FUTURE OF PRESENTING", 14, MUTED, bold=True)
text(s, 0.8, 1.6, 7.4, 3.6, "The slide\nis the easy\npart.", 72, CREAM, bold=True, spacing=0.92)
text(s, 0.8, 5.55, 6.6, 0.9, "AI and the next generation of presentation tools", 22, CYAN)
notes(s, "Welcome everyone. Tonight I want to talk about the part of presenting that AI has barely touched yet. Making slides got easy. Standing up and giving the talk is still as hard as it ever was.")

# 2 Statement
s = prs.slides.add_slide(blank); bg(s, DEEP)
text(s, 0.8, 1.3, 8.4, 4, "AI can write\nthe deck.\nIt can't give\nthe talk.", 58, CREAM, bold=True, spacing=0.96)
shape(s, MSO_SHAPE.RECTANGLE, 9.6, 1.3, 2.9, 3.9, None, line=VIOLET, lw=2.5)
shape(s, MSO_SHAPE.RECTANGLE, 10.0, 1.75, 2.1, 0.2, MUTED)
shape(s, MSO_SHAPE.RECTANGLE, 10.0, 2.15, 1.5, 0.2, DIM)
shape(s, MSO_SHAPE.OVAL, 10.55, 3.0, 1.0, 1.0, AMBER)
text(s, 0.8, 6.0, 9, 0.6, "That part is still you, a room, and a clock.", 22, AMBER)
notes(s, "Here is the thing. You can ask a model for twenty slides and get them in a minute. But nobody can give the talk for you. That part is still you, a room full of people, and a clock.")

# 3 Three shifts
s = prs.slides.add_slide(blank); bg(s, INK)
text(s, 0.8, 0.6, 9, 0.5, "THREE SHIFTS", 14, AMBER, bold=True)
text(s, 0.8, 1.05, 11.5, 1, "Where the tools are going next", 40, CREAM, bold=True)
for i, (t, b, c) in enumerate([
        ("Drafting", "From a blank page to a first deck in minutes.", VIOLET),
        ("Delivery", "Tools that listen, follow your script and keep your place.", CYAN),
        ("Feedback", "Pace, timing and filler words after every rehearsal.", AMBER)]):
    x = 0.8 + i * 4.0
    shape(s, MSO_SHAPE.ROUNDED_RECTANGLE, x, 2.6, 3.6, 3.9, DEEP)
    shape(s, MSO_SHAPE.RECTANGLE, x, 2.6, 3.6, 0.12, c)
    text(s, x + 0.4, 3.1, 2.9, 0.4, f"0{i + 1}", 18, c, bold=True)
    text(s, x + 0.4, 3.7, 2.9, 0.6, t, 30, CREAM, bold=True)
    text(s, x + 0.4, 4.5, 2.9, 1.7, b, 18, MUTED)
notes(s, "I see three shifts. Drafting is already solved. Delivery is next: tools that listen to you and keep your place. And feedback, so every rehearsal tells you something.")

# 4 Timeline
s = prs.slides.add_slide(blank); bg(s, DEEP)
text(s, 0.8, 0.6, 9, 0.5, "HOW WE GOT HERE", 14, AMBER, bold=True)
text(s, 0.8, 1.05, 11.5, 1, "From clicker to co-pilot", 40, CREAM, bold=True)
line(s, 1.2, 4.2, 12.2, 4.2, DIM, 3)
for i, (t, c) in enumerate([("Clicker", MUTED), ("Presenter view", MUTED), ("Prompter that listens", CYAN), ("Co-pilot", AMBER)]):
    x = 1.2 + i * 3.65
    shape(s, MSO_SHAPE.OVAL, x - 0.25, 3.95, 0.5, 0.5, c)
    text(s, x - 1.2, 4.75, 2.4, 1, t, 20, CREAM, bold=True, align=PP_ALIGN.CENTER)
notes(s, "We went from a clicker, to a presenter view, to prompters that actually listen. The next step is a co-pilot that sits next to you on stage and never takes the microphone.")

# 5 Quote
s = prs.slides.add_slide(blank); bg(s, AMBER)
text(s, 1.2, 1.6, 11, 3.4, "“The best tool on stage is\nthe one nobody else can see.”", 54, INK, bold=True, spacing=1.0)
text(s, 1.2, 5.3, 8, 0.6, "Overheard backstage", 20, INK)
notes(s, "Someone said this to me backstage once, and it stuck. The best tool on stage is the one nobody else can see.")

# 6 Close
s = prs.slides.add_slide(blank); bg(s, INK)
network(s, 0.6, 0.4, 12.1, 1.6, 14)
text(s, 0.8, 2.6, 11.7, 2, "Let the tools move with the speaker.", 54, CREAM, bold=True, align=PP_ALIGN.CENTER)
text(s, 0.8, 4.3, 11.7, 0.8, "Thank you · Questions", 24, AMBER, align=PP_ALIGN.CENTER)
notes(s, "So that is my ask for the people building these tools. Let them move with the speaker, not the other way around. Thank you. I would love to take your questions.")

out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "Samples" / "Sample.pptx"
prs.save(out)
print("saved", out)
