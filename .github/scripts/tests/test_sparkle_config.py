import base64
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "verify-sparkle-config.py"


class SparkleConfigTests(unittest.TestCase):
    def verify(self, content):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            path.write_bytes(content)
            return subprocess.run(["python3", str(SCRIPT), str(path)], capture_output=True, text=True)

    def test_valid_exported_key(self):
        result = self.verify(plistlib.dumps({"SUPublicEDKey": base64.b64encode(b"x" * 32).decode()}))
        self.assertEqual(result.returncode, 0)

    def test_unusable_exported_keys_fail_before_notarization(self):
        for info in [{}, {"SUPublicEDKey": ""}, {"SUPublicEDKey": "$(SPARKLE_PUBLIC_ED_KEY)"},
                     {"SUPublicEDKey": 123}, {"SUPublicEDKey": base64.b64encode(b"x" * 31).decode()}]:
            with self.subTest(info=info):
                result = self.verify(plistlib.dumps(info))
                self.assertEqual(result.returncode, 1)
                self.assertIn("valid 32-byte SUPublicEDKey", result.stderr)

    def test_invalid_plist_is_rejected(self):
        result = self.verify(b"not a plist")
        self.assertEqual(result.returncode, 1)
        self.assertIn("valid 32-byte SUPublicEDKey", result.stderr)


if __name__ == "__main__":
    unittest.main()
