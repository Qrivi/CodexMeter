from pathlib import Path
import subprocess
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "check-release-order.py"


class ReleaseOrderTests(unittest.TestCase):
    def check(self, candidate, published):
        return subprocess.run(["python3", str(SCRIPT), candidate], input="\n".join(published),
                              capture_output=True, text=True)

    def test_first_release_new_release_and_latest_retry_are_allowed(self):
        for published in [[], ["v1.2.1"], ["v1.3.0", "v1.2.1"]]:
            with self.subTest(published=published):
                self.assertEqual(self.check("v1.3.0", published).returncode, 0)

    def test_older_retry_is_rejected_regardless_of_release_order(self):
        result = self.check("v1.3.0", ["v1.2.1", "v1.3.1", "v1.1.0"])
        self.assertEqual(result.returncode, 1)
        self.assertIn("newer stable release", result.stderr)

    def test_versions_are_compared_numerically(self):
        self.assertEqual(self.check("v1.10.0", ["v1.9.9"]).returncode, 0)
        self.assertEqual(self.check("v1.9.9", ["v1.10.0"]).returncode, 1)

    def test_nonstable_tags_do_not_block_a_stable_release(self):
        self.assertEqual(self.check("v1.3.0", ["v1.4.0-beta.1", "nightly"]).returncode, 0)

    def test_invalid_candidate_is_rejected(self):
        result = self.check("develop", [])
        self.assertEqual(result.returncode, 1)
        self.assertIn("Expected a stable", result.stderr)


if __name__ == "__main__":
    unittest.main()
