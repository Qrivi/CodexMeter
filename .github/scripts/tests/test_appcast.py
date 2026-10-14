"""Verify feed validation and secret handling without production signing keys."""

import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "generate-appcast.sh"
SECRET = "FAKE-SPARKLE-PRIVATE-KEY"


class AppcastTests(unittest.TestCase):
    def run_generator(self, mode):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / "tools"
            tools.mkdir()
            generator = tools / "generate_appcast"
            generator.write_text("""#!/usr/bin/env python3
import base64, os, pathlib, sys
key = sys.stdin.read()
assert key == os.environ['SPARKLE_PRIVATE_KEY']
assert key not in ' '.join(sys.argv)
pathlib.Path(os.environ['TEST_CALLED']).write_text('stdin key received')
print(key)
print(key, file=sys.stderr)
mode = os.environ['TEST_MODE']
feed = pathlib.Path(sys.argv[sys.argv.index('-o') + 1])
if mode == 'tool_failure':
    feed.write_text(key)
    sys.exit(1)
prefix = sys.argv[sys.argv.index('--download-url-prefix') + 1]
signature = '' if mode == 'unsigned' else base64.b64encode(b'x' * 64).decode()
url = 'https://example.invalid/wrong.dmg' if mode == 'wrong_url' else prefix + 'CodexMeter-v1.3.0-arm64.dmg'
length = 99 if mode == 'wrong_length' else 4
version = '1' if mode == 'wrong_build' else '123'
description = key if mode == 'key_in_feed' else 'Update available'
feed.write_text(f'''<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
<channel><item><sparkle:version>{version}</sparkle:version><description>{description}</description>
<enclosure url="{url}" length="{length}" sparkle:edSignature="{signature}"/></item></channel></rss>''')
""")
            generator.chmod(0o700)
            dmg = root / "CodexMeter-v1.3.0-arm64.dmg"
            dmg.write_bytes(b"test")
            output = root / "feeds"
            env = dict(os.environ, RUNNER_TEMP=str(root), SPARKLE_PRIVATE_KEY=SECRET,
                       TEST_MODE=mode, TEST_CALLED=str(root / "called"))
            result = subprocess.run(
                ["bash", str(SCRIPT), str(tools), str(dmg), "arm64", "v1.3.0", "123", str(output)],
                env=env, capture_output=True, text=True, check=False,
            )
            self.assertNotIn(SECRET, result.stdout + result.stderr)
            self.assertEqual((root / "called").read_text(), "stdin key received")
            self.assertEqual(list(root.glob("sparkle-private.*")), [])
            feed = output / "appcast-arm64.xml"
            if mode == "valid":
                self.assertEqual(result.returncode, 0)
                self.assertTrue(feed.exists())
                self.assertNotIn(SECRET, feed.read_text())
                self.assertEqual(result.stderr, "")
            else:
                self.assertEqual(result.returncode, 1)
                self.assertFalse(feed.exists())
                expected = "generation failed" if mode == "tool_failure" else "validation failed"
                self.assertIn(expected, result.stderr)

    def test_valid_feed_is_retained(self):
        self.run_generator("valid")

    def test_invalid_or_unsigned_feeds_are_rejected(self):
        for mode in ["unsigned", "wrong_url", "wrong_length", "wrong_build"]:
            with self.subTest(mode=mode):
                self.run_generator(mode)

    def test_tool_failure_output_and_partial_feed_stay_private(self):
        self.run_generator("tool_failure")

    def test_private_key_in_feed_is_rejected_and_deleted(self):
        self.run_generator("key_in_feed")


if __name__ == "__main__":
    unittest.main()
