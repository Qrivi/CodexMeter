"""Exercise publication and retries against a local fake GitHub release."""

import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


SCRIPTS = Path(__file__).resolve().parents[1]
TAG = "v1.3.0"
NAMES = [f"CodexMeter-{TAG}-{arch}.dmg" for arch in ["arm64", "x86_64"]]
NOTES = "# Release\n\nExact notes, including `code` and $symbols.\n"


class ReleaseAssetTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.release = self.root / "release"
        self.release.mkdir()
        for name in NAMES:
            (self.release / name).write_bytes(b"rebuilt " + name.encode())
        notes = self.root / ".github/release-notes" / f"{TAG}.md"
        notes.parent.mkdir(parents=True)
        notes.write_text(NOTES)
        self.remote = self.root / "remote"
        self.remote.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        gh = self.bin / "gh"
        gh.write_text('''#!/usr/bin/env python3
import json, os, pathlib, shutil, sys
args = sys.argv[1:]
remote = pathlib.Path(os.environ['TEST_REMOTE'])
with (remote / 'calls').open('a') as log:
    log.write(json.dumps(args) + '\\n')
if args[0] == 'api':
    assert '--paginate' in args
    if os.environ.get('TEST_API_FAILURE'):
        sys.exit('API unavailable')
    if (remote / 'exists').exists():
        print('v1.3.0')
        for asset in sorted(remote.glob('*.dmg')):
            print(asset.name)
elif args[:2] == ['release', 'download']:
    if os.environ.get('TEST_DOWNLOAD_FAILURE'):
        sys.exit('Download failed')
    name = args[args.index('--pattern') + 1]
    destination = pathlib.Path(args[args.index('--dir') + 1])
    shutil.copyfile(remote / name, destination / name)
elif args[:2] in [['release', 'create'], ['release', 'upload']]:
    assert '--clobber' not in args
    if args[1] == 'create':
        assert not (remote / 'exists').exists()
        assert '--verify-tag' in args
        (remote / 'exists').touch()
    for arg in args[3:]:
        if arg.endswith('.dmg'):
            source = pathlib.Path(arg)
            assert not (remote / source.name).exists(), 'Cannot replace an asset'
            shutil.copyfile(source, remote / source.name)
    if '--notes-file' in args:
        shutil.copyfile(args[args.index('--notes-file') + 1], remote / 'notes')
elif args[:2] == ['release', 'edit']:
    shutil.copyfile(args[args.index('--notes-file') + 1], remote / 'notes')
else:
    sys.exit('Unexpected gh command')
''')
        gh.chmod(0o700)
        self.env = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                        GH_REPO="Qrivi/CodexMeter", RUNNER_TEMP=str(self.root),
                        TEST_REMOTE=str(self.remote))

    def run_assets(self, mode, path, **environment):
        result = subprocess.run(
            ["bash", str(SCRIPTS / "release-assets.sh"), mode, TAG, str(path)],
            cwd=self.root, env=dict(self.env, **environment), capture_output=True, text=True,
        )
        self.assertEqual(list(self.root.glob("release-assets.*")), [])
        return result

    def seed_remote(self, names=NAMES):
        (self.remote / "exists").touch()
        for name in names:
            (self.remote / name).write_bytes(b"original " + name.encode())

    def calls(self):
        return [json.loads(line) for line in (self.remote / "calls").read_text().splitlines()]

    def test_first_publication_uploads_both_assets_and_exact_notes(self):
        for name in NAMES:
            self.assertEqual(self.run_assets("reuse", self.release / name).returncode, 0)
        result = self.run_assets("publish", self.release)
        self.assertEqual(result.returncode, 0, result.stderr)
        for name in NAMES:
            self.assertEqual((self.remote / name).read_bytes(), (self.release / name).read_bytes())
        self.assertEqual((self.remote / "notes").read_text(), NOTES)

    def test_full_retry_preserves_original_bytes_and_updates_notes(self):
        self.seed_remote()
        for name in NAMES:
            result = self.run_assets("reuse", self.release / name)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((self.release / name).read_bytes(), b"original " + name.encode())
        result = self.run_assets("publish", self.release)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(call[:2] == ["release", "upload"] for call in self.calls()))
        self.assertEqual((self.remote / "notes").read_text(), NOTES)

    def test_retry_feed_covers_the_original_published_dmg(self):
        self.seed_remote()
        dmg = self.release / NAMES[0]
        self.assertEqual(self.run_assets("reuse", dmg).returncode, 0)
        generator = self.bin / "generate_appcast"
        # Use a content digest as the mock signature to detect signing rebuilt bytes.
        generator.write_text("""#!/usr/bin/env python3
import base64, hashlib, html, pathlib, sys
sys.stdin.read()
args = sys.argv[1:]
dmg = next(pathlib.Path(args[-1]).glob('*.dmg'))
signature = base64.b64encode(hashlib.sha512(dmg.read_bytes()).digest()).decode()
prefix = args[args.index('--download-url-prefix') + 1]
notes = dmg.with_suffix('.md').read_text()
pathlib.Path(args[args.index('-o') + 1]).write_text(f'''
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>
<sparkle:version>123</sparkle:version>
<description sparkle:format="markdown">{html.escape(notes)}</description>
<enclosure url="{prefix}{dmg.name}" length="{dmg.stat().st_size}" sparkle:edSignature="{signature}"/>
</item></channel></rss>''')
""")
        generator.chmod(0o700)
        feeds = self.root / "feeds"
        result = subprocess.run(
            ["bash", str(SCRIPTS / "generate-appcast.sh"), str(self.bin), str(dmg),
             "arm64", TAG, "123", str(feeds)],
            env=dict(self.env, SPARKLE_PRIVATE_KEY="test-key"), capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        enclosure = ET.parse(feeds / "appcast-arm64.xml").find("./channel/item/enclosure")
        signature = enclosure.get("{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature")
        self.assertEqual(base64.b64decode(signature), hashlib.sha512((self.remote / NAMES[0]).read_bytes()).digest())

    def test_partial_publication_uploads_only_the_missing_asset(self):
        self.seed_remote(NAMES[:1])
        for name in NAMES:
            self.assertEqual(self.run_assets("reuse", self.release / name).returncode, 0)
        result = self.run_assets("publish", self.release)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.remote / NAMES[0]).read_bytes(), b"original " + NAMES[0].encode())
        uploads = [call for call in self.calls() if call[:2] == ["release", "upload"]]
        self.assertEqual(uploads, [["release", "upload", TAG, str(self.release / NAMES[1])]])

    def test_existing_release_with_no_assets_is_recovered(self):
        self.seed_remote([])
        result = self.run_assets("publish", self.release)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(all((self.remote / name).exists() for name in NAMES))

    def test_changed_asset_aborts_before_upload_or_feed_publication(self):
        self.seed_remote(NAMES[1:])
        result = self.run_assets("publish", self.release)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Refusing to replace", result.stderr)
        self.assertFalse((self.remote / NAMES[0]).exists())
        self.assertFalse((self.remote / "notes").exists())

    def test_api_failure_never_falls_back_to_publication(self):
        for mode, path in [("reuse", self.release / NAMES[0]), ("publish", self.release)]:
            with self.subTest(mode=mode):
                result = self.run_assets(mode, path, TEST_API_FAILURE="1")
                self.assertNotEqual(result.returncode, 0)
        self.assertFalse((self.remote / "exists").exists())

    def test_failed_download_does_not_replace_original_or_publish(self):
        self.seed_remote()
        dmg = self.release / NAMES[0]
        rebuilt = dmg.read_bytes()
        for mode, path in [("reuse", dmg), ("publish", self.release)]:
            with self.subTest(mode=mode):
                result = self.run_assets(mode, path, TEST_DOWNLOAD_FAILURE="1")
                self.assertNotEqual(result.returncode, 0)
        self.assertEqual(dmg.read_bytes(), rebuilt)
        self.assertFalse((self.remote / "notes").exists())


if __name__ == "__main__":
    unittest.main()
