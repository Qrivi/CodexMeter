#!/bin/bash
set -euo pipefail

mode="${1:?Expected reuse or publish}"
tag="${2:?Expected release tag}"
asset_path="${3:?Expected DMG path or release directory}"
case "${mode}" in reuse|publish) ;; *) echo "Invalid release asset operation." >&2; exit 1 ;; esac
if [[ ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a stable v<major>.<minor>.<patch> release tag." >&2
  exit 1
fi

# Listing releases distinguishes a missing release from an API/authentication failure.
# Include the tag itself so an existing release with no assets is still recognized.
published="$(gh api --paginate "repos/${GH_REPO:?}/releases" \
  --jq ".[] | select(.tag_name == \"${tag}\") | .tag_name, .assets[].name")"
download_dir="$(mktemp -d "${RUNNER_TEMP}/release-assets.XXXXXX")"
trap 'rm -rf "${download_dir}"' EXIT

download_asset() {
  gh release download "${tag}" --pattern "$1" --dir "${download_dir}"
}

if [[ "${mode}" == reuse ]]; then
  asset_name="$(basename "${asset_path}")"
  if grep -Fxq "${asset_name}" <<< "${published}"; then
    download_asset "${asset_name}"
    # Generate the feed from the original bytes, including on a full workflow retry.
    mv "${download_dir}/${asset_name}" "${asset_path}"
    echo "Reusing published ${asset_name}."
  fi
  exit 0
fi

notes_path=".github/release-notes/${tag}.md"
assets=("${asset_path}/CodexMeter-${tag}-arm64.dmg" "${asset_path}/CodexMeter-${tag}-x86_64.dmg")
for asset in "${assets[@]}"; do
  test -f "${asset}"
done

if grep -Fxq "${tag}" <<< "${published}"; then
  missing_assets=()
  for asset in "${assets[@]}"; do
    asset_name="$(basename "${asset}")"
    if grep -Fxq "${asset_name}" <<< "${published}"; then
      download_asset "${asset_name}"
      if ! cmp -s "${asset}" "${download_dir}/${asset_name}"; then
        echo "Published ${asset_name} differs from the feed's DMG. Refusing to replace it or publish mismatched feeds." >&2
        exit 1
      fi
    else
      missing_assets+=("${asset}")
    fi
  done
  # Recover partial publications without ever replacing a published download.
  if (( ${#missing_assets[@]} > 0 )); then
    gh release upload "${tag}" "${missing_assets[@]}"
  fi
  gh release edit "${tag}" --notes-file "${notes_path}"
else
  gh release create "${tag}" "${assets[@]}" \
    --title "CodexMeter ${tag}" \
    --notes-file "${notes_path}" \
    --verify-tag
fi
