import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "release-metadata.sh"


class ReleaseMetadataTests(unittest.TestCase):
    def metadata(self, *, dry_run=False, ref_type="tag", ref="v1.3.0", build="", version="1.3.0"):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            git = root / "git"
            git.write_text("#!/bin/sh\necho 123\n")
            git.chmod(0o700)
            xcode = root / "xcodebuild"
            xcode.write_text("""#!/usr/bin/env python3
import os, sys
assert '-onlyUsePackageVersionsFromResolvedFile' in sys.argv
print('MARKETING_VERSION = ' + os.environ['TEST_VERSION'])
""")
            xcode.chmod(0o700)
            output = root / "output"
            env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", GITHUB_OUTPUT=str(output),
                       DRY_RUN=str(dry_run).lower(), GITHUB_REF_TYPE=ref_type, GITHUB_REF_NAME=ref,
                       TEST_BUILD_NUMBER=build, TEST_VERSION=version)
            result = subprocess.run(["bash", str(SCRIPT)], env=env, capture_output=True, text=True)
            return result, output.read_text() if output.exists() else ""

    def test_production_uses_tag_and_commit_count(self):
        result, output = self.metadata()
        self.assertEqual(result.returncode, 0)
        self.assertEqual(output, "tag=v1.3.0\nversion=1.3.0\nnumber=123\n")

    def test_branch_requires_build_only_mode(self):
        result, output = self.metadata(ref_type="branch", ref="develop")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Production releases require", result.stderr)
        self.assertEqual(output, "")

    def test_build_only_reads_project_version_and_allows_test_build_number(self):
        result, output = self.metadata(dry_run=True, ref_type="branch", ref="develop", build="1000")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(output, "tag=v1.3.0\nversion=1.3.0\nnumber=1000\n")

    def test_production_cannot_override_build_number(self):
        result, output = self.metadata(build="1000")
        self.assertEqual(result.returncode, 1)
        self.assertIn("only allowed with dry_run", result.stderr)
        self.assertEqual(output, "")

    def test_invalid_test_metadata_is_rejected(self):
        for overrides in [{"version": "1.3.0-beta"}, {"build": "0"}, {"build": "-1"}, {"build": "text"}]:
            with self.subTest(overrides=overrides):
                result, output = self.metadata(dry_run=True, **overrides)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(output, "")


if __name__ == "__main__":
    unittest.main()
