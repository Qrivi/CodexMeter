"""Exercise notarization logging without Apple credentials or network access."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "notarize.sh"
SUBMISSION_ID = "12345678-1234-1234-1234-123456789abc"
SENTINEL = "FAKE-PRIVATE-CREDENTIAL-MUST-NOT-APPEAR"


class NotarizationPrivacyTests(unittest.TestCase):
    def run_notarization(self, status="Accepted", command_exit=0, malformed=False, injected_fields=False, log_exit=0):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / "tools"
            tools.mkdir()
            stub = tools / "xcrun"
            stub.write_text("""#!/usr/bin/env python3
import json, os, pathlib, sys
sentinel = os.environ['TEST_SENTINEL']
print(sentinel, file=sys.stderr)
if sys.argv[2] == 'submit':
    if os.environ['TEST_MALFORMED'] == '1':
        print(sentinel)
    else:
        injected = os.environ['TEST_INJECTED'] == '1'
        print(json.dumps({
            'id': sentinel if injected else os.environ['TEST_ID'],
            'status': sentinel if injected else os.environ['TEST_STATUS'],
            'message': sentinel, 'path': sentinel, 'url': 'https://example.invalid/' + sentinel
        }))
    sys.exit(int(os.environ['TEST_EXIT']))
if sys.argv[2] == 'log':
    print(sentinel)
    pathlib.Path(sys.argv[-1]).write_text(json.dumps({
        'developerId': sentinel, 'ticketContents': sentinel,
        'issues': [
            {'severity': 'error', 'code': 4000, 'message': sentinel, 'path': sentinel},
            {'severity': sentinel, 'code': sentinel, 'message': sentinel}
        ]
    }))
    sys.exit(int(os.environ['TEST_LOG_EXIT']))
raise SystemExit('Unexpected mock command')
""")
            stub.chmod(0o700)
            env = dict(
                os.environ,
                PATH=f"{tools}{os.pathsep}{os.environ['PATH']}",
                RUNNER_TEMP=str(root),
                TEST_SENTINEL=SENTINEL,
                TEST_ID=SUBMISSION_ID,
                TEST_STATUS=status,
                TEST_EXIT=str(command_exit),
                TEST_LOG_EXIT=str(log_exit),
                TEST_MALFORMED=str(int(malformed)),
                TEST_INJECTED=str(int(injected_fields)),
            )
            result = subprocess.run(
                ["bash", str(SCRIPT), "/tmp/fake-app.zip", "app"],
                env=env, capture_output=True, text=True, check=False,
            )
            self.assertNotIn(SENTINEL, result.stdout + result.stderr)
            self.assertEqual(list(root.glob("notarization-private.*")), [])
            summaries = list(root.glob("notarization-*.json"))
            self.assertEqual([path.name for path in summaries], ["notarization-app-summary.json"])
            self.assertNotIn(SENTINEL, summaries[0].read_text())
            self.assertEqual(summaries[0].stat().st_mode & 0o777, 0o600)
            return result.returncode, json.loads(summaries[0].read_text())

    def test_accepted_response_excludes_raw_messages_and_errors(self):
        code, summary = self.run_notarization()
        self.assertEqual(code, 0)
        self.assertEqual(summary, {
            "id": SUBMISSION_ID, "status": "Accepted",
            "issues": [{"severity": "error", "code": 4000}, {"severity": "unknown", "code": None}],
        })

    def test_rejection_timeout_and_command_failure_remain_failures(self):
        for status, command_exit in [("Invalid", 0), ("Rejected", 0), ("In Progress", 0), ("Accepted", 1)]:
            with self.subTest(status=status, command_exit=command_exit):
                code, _ = self.run_notarization(status=status, command_exit=command_exit)
                self.assertNotEqual(code, 0)

    def test_malformed_response_is_private_and_fails_closed(self):
        code, summary = self.run_notarization(malformed=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(summary, {"id": None, "status": "Unknown"})

    def test_unexpected_values_in_allowed_fields_are_removed(self):
        code, summary = self.run_notarization(injected_fields=True)
        self.assertNotEqual(code, 0)
        self.assertEqual(summary, {"id": None, "status": "Unknown"})

    def test_failed_log_download_does_not_print_partial_response(self):
        code, summary = self.run_notarization(log_exit=1)
        self.assertEqual(code, 0)
        self.assertEqual(summary, {"id": SUBMISSION_ID, "status": "Accepted"})


if __name__ == "__main__":
    unittest.main()
