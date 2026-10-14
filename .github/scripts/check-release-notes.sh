#!/bin/bash
set -euo pipefail

tag="${1:?Usage: check-release-notes.sh <tag>}"
if [[ ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a stable v<major>.<minor>.<patch> release tag." >&2
  exit 1
fi

notes_path=".github/release-notes/${tag}.md"
if [[ ! -f "${notes_path}" ]] || ! grep -q '[^[:space:]]' "${notes_path}"; then
  echo "Add non-empty release notes at ${notes_path} before releasing ${tag}." >&2
  exit 1
fi

echo "Release notes found: ${notes_path}"
