#!/bin/bash
set +x
set -euo pipefail
umask 077

tools_dir="${1:?Expected Sparkle tools directory}"
dmg_path="${2:?Expected final DMG path}"
arch="${3:?Expected architecture}"
tag="${4:?Expected release tag}"
build_number="${5:?Expected build number}"
output_dir="${6:?Expected feed output directory}"

case "${arch}" in arm64|x86_64) ;; *) echo "Invalid update architecture." >&2; exit 1 ;; esac
if [[ ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ || ! "${build_number}" =~ ^[0-9]+$ ]]; then
  echo "Invalid update version." >&2
  exit 1
fi
if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "SPARKLE_PRIVATE_KEY is not configured." >&2
  exit 1
fi

private_dir="$(mktemp -d "${RUNNER_TEMP}/sparkle-private.XXXXXX")"
feed_path="${output_dir}/appcast-${arch}.xml"
cleanup() {
  result=$?
  rm -rf "${private_dir}"
  if [[ "${result}" != 0 ]]; then rm -f "${feed_path}"; fi
}
trap cleanup EXIT
mkdir -p "${private_dir}/archives" "${output_dir}"
cp "${dmg_path}" "${private_dir}/archives/"
download_url="https://github.com/Qrivi/CodexMeter/releases/download/${tag}/"

# The signing key goes through stdin, never command arguments or a key file.
# Tool output stays private because errors may contain credential information.
if ! printf '%s' "${SPARKLE_PRIVATE_KEY}" | "${tools_dir}/generate_appcast" \
  --ed-key-file - \
  --maximum-deltas 0 \
  --download-url-prefix "${download_url}" \
  --full-release-notes-url "https://github.com/Qrivi/CodexMeter/releases/tag/${tag}" \
  --link "https://github.com/Qrivi/CodexMeter" \
  -o "${feed_path}" "${private_dir}/archives" > "${private_dir}/tool.log" 2>&1; then
  echo "Sparkle feed generation failed. Check the signing secret matches the app's public key." >&2
  exit 1
fi

# Sparkle can finish with warnings and omit a signature when the key does not match.
if ! python3 - "${feed_path}" "${dmg_path}" "${download_url}" "${build_number}" <<'PY'
import base64
import os
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

try:
    feed, dmg, prefix, build = sys.argv[1:]
    content = Path(feed).read_text()
    if os.environ['SPARKLE_PRIVATE_KEY'].strip() in content:
        raise ValueError('Private key in feed')
    items = ET.fromstring(content).findall('./channel/item')
    if len(items) != 1:
        raise ValueError('Expected one update')
    enclosure = items[0].find('enclosure')
    namespace = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'
    if enclosure is None:
        raise ValueError('Missing enclosure')
    signature = enclosure.get(namespace + 'edSignature', '')
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError('Missing signature')
    if enclosure.get('url') != prefix + Path(dmg).name:
        raise ValueError('Unexpected download URL')
    if int(enclosure.get('length', '-1')) != Path(dmg).stat().st_size:
        raise ValueError('Unexpected download length')
    if items[0].findtext(namespace + 'version') != build:
        raise ValueError('Unexpected build number')
except Exception:
    print('Sparkle feed validation failed. Nothing will be published.', file=sys.stderr)
    sys.exit(1)
PY
then
  rm -f "${feed_path}"
  exit 1
fi

echo "Signed and validated ${arch} update feed."
