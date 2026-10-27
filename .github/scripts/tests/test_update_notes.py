import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "generate-update-notes.py"
SPEC = importlib.util.spec_from_file_location("update_notes", SCRIPT)
UPDATE_NOTES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UPDATE_NOTES)


class UpdateNotesTests(unittest.TestCase):
    def test_combines_releases_in_numeric_order_without_future_or_installed_versions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for version in ["1.2.0", "1.9.0", "1.10.0", "1.11.0"]:
                (root / f"v{version}.md").write_text(f"Summary for {version}.\n\n## Highlights\n\n- Fixed {version}.\n")
            (root / "v1.10.0-beta.1.md").write_text("Not a stable release.")
            notes = UPDATE_NOTES.combined_notes(root, "v1.10.0", "1.2.0")
            self.assertLess(notes.index("# Version 1.10.0"), notes.index("# Version 1.9.0"))
            self.assertNotIn("1.2.0", notes)
            self.assertNotIn("1.11.0", notes)
            self.assertNotIn("beta", notes)
            self.assertNotIn("## Highlights", notes)
            self.assertIn("- Fixed 1.10.0.", notes)
            self.assertTrue(notes.endswith(UPDATE_NOTES.HISTORY_LINK + "\n"))

    def test_default_includes_older_versions_for_client_side_filtering(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "v1.0.0.md").write_text("First release.")
            (root / "v1.1.0.md").write_text("New release.")
            notes = UPDATE_NOTES.combined_notes(root, "v1.1.0")
            self.assertIn("# Version 1.0.0", notes)
            self.assertIn("# Version 1.1.0", notes)
            self.assertEqual(notes.count(UPDATE_NOTES.HISTORY_LINK), 1)

    def test_missing_or_empty_target_notes_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            with self.assertRaises(ValueError):
                UPDATE_NOTES.combined_notes(root, "v1.3.1")
            (root / "v1.3.1.md").write_text(" \n")
            with self.assertRaises(ValueError):
                UPDATE_NOTES.combined_notes(root, "v1.3.1")

    def test_example_upgrade_contains_exactly_the_three_missed_releases(self):
        root = SCRIPT.parents[1] / "release-notes"
        notes = UPDATE_NOTES.combined_notes(root, "v1.3.1", "1.2.0")
        headings = [line for line in notes.splitlines() if line.startswith("# Version ")]
        self.assertEqual(headings, ["# Version 1.3.1", "# Version 1.3.0", "# Version 1.2.1"])


if __name__ == "__main__":
    unittest.main()
