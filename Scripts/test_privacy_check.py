"""Tests for Scripts/privacy_check.py:  python3 -I -m unittest discover -s Scripts -p 'test_*.py'"""
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import privacy_check as pc  # noqa: E402


def findings(text, terms=()):
    found = pc.Findings()
    pc.check_text("f:1", text, [(t, pc.term_pattern(t)) for t in terms], found)
    return found.items


class Checks(unittest.TestCase):
    # Test data is assembled from pieces so this file doesn't trip the checker itself.
    NAME = "Quill" + "andra"
    HEBREW = "קווי" + "לנדה"
    ADDRESS = "someone" + "@" + "realcompany.co"
    PHONES = ("+1 415 " + "555 0134", "054-" + "123-4567")

    def test_private_name_is_masked(self):
        items = findings(f"Thanks to {self.NAME} for the slides", [self.NAME])
        self.assertEqual(len(items), 1)
        self.assertNotIn(self.NAME, items[0])

    def test_hebrew_name_with_prefix(self):
        self.assertTrue(findings("שלום ל" + self.HEBREW, [self.HEBREW]))

    def test_allowed_and_blocked_addresses(self):
        self.assertFalse(findings("write to sam@example.com"))
        self.assertFalse(findings("1234+someone@users.noreply.github.com"))
        self.assertTrue(findings("write to " + self.ADDRESS))

    def test_phone_numbers(self):
        for phone in self.PHONES:
            self.assertTrue(findings("call " + phone))
        self.assertFalse(findings("call +972500000000"))   # placeholder
        self.assertFalse(findings("version 1.2.3 on port 8765"))

    def test_build_terms_skips_allowed_words(self):
        self.assertEqual(pc.build_terms({"Sam", self.NAME + " Smith"}, {"sam"}), [self.NAME + " Smith", self.NAME])

    def test_screenshot_outside_allowed_folders_is_blocked(self):
        found = pc.Findings()
        pc.check_files("A\tdocs/screenshot.png\nA\tdocs/images/render.png\nA\tResources/AppIcon.icns", found)
        self.assertEqual(len(found.items), 1)
        self.assertIn("docs/screenshot.png", found.items[0])


class InARepository(unittest.TestCase):
    def test_blocks_a_commit_with_a_real_address(self):
        with tempfile.TemporaryDirectory() as d:
            env = {**os.environ, "BEMA_REPO": d, "BEMA_SKIP_GITLEAKS": "1",
                   "BEMA_PRIVATE_TERMS": str(Path(d) / "none.txt")}
            run = lambda *a: subprocess.run(a, cwd=d, env=env, capture_output=True, text=True)  # noqa: E731
            run("git", "init", "-q")
            Path(d, "notes.md").write_text("Contact: " + Checks.ADDRESS + "\n")
            run("git", "add", "notes.md")
            r = run(sys.executable, "-I", str(Path(__file__).resolve().parent / "privacy_check.py"), "staged")
            self.assertEqual(r.returncode, 1)
            self.assertIn("realcompany.co", r.stderr)


if __name__ == "__main__":
    unittest.main()
