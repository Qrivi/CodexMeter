#!/bin/bash
set +x
set -euo pipefail
umask 077

archive_path="${1:?Expected archive path}"
label="${2:?Expected diagnostic label}"
case "${label}" in app|dmg) ;; *) echo "Invalid diagnostic label." >&2; exit 1 ;; esac
keychain_path="${RUNNER_TEMP}/signing.keychain-db"
summary_path="${RUNNER_TEMP}/notarization-${label}-summary.json"
private_dir="$(mktemp -d "${RUNNER_TEMP}/notarization-private.XXXXXX")"
trap 'rm -rf "${private_dir}"' EXIT
result_path="${private_dir}/submission.json"
log_path="${private_dir}/log.json"

# Raw responses and tool errors stay private; GitHub artifact files are not log-masked.
submission_exit=0
xcrun notarytool submit "${archive_path}" \
  --keychain-profile CodexMeter \
  --keychain "${keychain_path}" \
  --wait --timeout 60m --output-format json > "${result_path}" 2> "${private_dir}/stderr" || submission_exit=$?

# Allowlist values as well as field names. Never publish free-form messages or URLs.
if ! jq '{
  id: (if (.id | type) == "string" then
    (if (.id | test("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")) then .id else null end)
    else null end),
  status: (if (.status == "Accepted" or .status == "Invalid" or .status == "Rejected" or .status == "In Progress")
    then .status else "Unknown" end)
}' "${result_path}" > "${summary_path}" 2> /dev/null; then
  printf '%s\n' '{"id":null,"status":"Unknown"}' > "${summary_path}"
fi

submission_id="$(jq -r '.id // empty' "${summary_path}")"
if [[ -n "${submission_id}" ]]; then
  if xcrun notarytool log "${submission_id}" \
    --keychain-profile CodexMeter \
    --keychain "${keychain_path}" "${log_path}" > "${private_dir}/stdout" 2> "${private_dir}/stderr"; then
    if jq '{issues: (if (.issues | type) == "array" then [.issues[] | {
      severity: (if (.severity == "error" or .severity == "warning") then .severity else "unknown" end),
      code: (if (.code | type) == "number" then .code else null end)
    }] else [] end)}' "${log_path}" > "${private_dir}/issues.json" 2> /dev/null; then
      jq -s '.[0] + .[1]' "${summary_path}" "${private_dir}/issues.json" > "${private_dir}/summary.json"
      cp "${private_dir}/summary.json" "${summary_path}"
    fi
  fi
fi

cat "${summary_path}"
if [[ "${submission_exit}" != 0 ]] || ! jq -e '.status == "Accepted" and .id != null' "${summary_path}" > /dev/null; then
  echo "Notarization did not complete with Accepted status. See the safe summary; retrieve detailed logs privately from Apple using the submission ID." >&2
  exit 1
fi
