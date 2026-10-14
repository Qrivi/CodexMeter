from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "check-release-notes.sh"


class ReleaseNotesTests(unittest.TestCase):
    def check(self, *, tag="v1.3.0", filename="v1.3.0.md", content=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            if content is not None:
                notes = root / ".github/release-notes" / filename
                notes.parent.mkdir(parents=True)
                notes.write_text(content)
            return subprocess.run(["bash", str(SCRIPT), tag], cwd=root,
                                  capture_output=True, text=True)

    def test_matching_notes_are_accepted(self):
        result = self.check(content="# New release\n\n- Improved updates.\n")
        self.assertEqual(result.returncode, 0)
        self.assertIn(".github/release-notes/v1.3.0.md", result.stdout)

    def test_missing_notes_are_rejected(self):
        result = self.check()
        self.assertEqual(result.returncode, 1)
        self.assertIn("Add non-empty release notes at .github/release-notes/v1.3.0.md", result.stderr)

    def test_different_version_does_not_satisfy_requirement(self):
        result = self.check(filename="v1.3.1.md", content="# Another release\n")
        self.assertEqual(result.returncode, 1)
        self.assertIn(".github/release-notes/v1.3.0.md", result.stderr)

    def test_empty_or_whitespace_only_notes_are_rejected(self):
        for content in ["", " \n\t\n"]:
            with self.subTest(content=content):
                result = self.check(content=content)
                self.assertEqual(result.returncode, 1)
                self.assertIn("Add non-empty release notes", result.stderr)

    def test_nonstable_version_is_rejected(self):
        result = self.check(tag="v1.3.0-beta.1")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Expected a stable", result.stderr)


if __name__ == "__main__":
    unittest.main()
