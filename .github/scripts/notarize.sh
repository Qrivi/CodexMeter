#!/bin/bash
set -euo pipefail

archive_path="${1:?Expected archive path}"
label="${2:?Expected diagnostic label}"
keychain_path="${RUNNER_TEMP}/signing.keychain-db"
result_path="${RUNNER_TEMP}/notarization-${label}-submission.json"
log_path="${RUNNER_TEMP}/notarization-${label}-log.json"

# Keep Apple's submission ID and diagnostics even if the submission is rejected.
submission_exit=0
xcrun notarytool submit "${archive_path}" \
  --keychain-profile CodexMeter \
  --keychain "${keychain_path}" \
  --wait --timeout 60m --output-format json > "${result_path}" || submission_exit=$?

cat "${result_path}"
submission_id="$(jq -r '.id // empty' "${result_path}")"
if [[ -n "${submission_id}" ]]; then
  xcrun notarytool log "${submission_id}" \
    --keychain-profile CodexMeter \
    --keychain "${keychain_path}" "${log_path}" || true
fi

if [[ "${submission_exit}" != 0 ]] || ! jq -e '.status == "Accepted"' "${result_path}" > /dev/null; then
  echo "Notarization did not complete with Accepted status. See notarization diagnostics." >&2
  exit 1
fi
