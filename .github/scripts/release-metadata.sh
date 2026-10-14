#!/bin/bash
set -euo pipefail

dry_run="${DRY_RUN:-false}"
if [[ "${dry_run}" == true ]]; then
  version="$(xcodebuild -showBuildSettings \
    -project CodexMeter.xcodeproj -scheme CodexMeter -configuration Release \
    -onlyUsePackageVersionsFromResolvedFile \
    | awk -F'= ' '/MARKETING_VERSION/ {print $2; exit}')"
  tag="v${version}"
else
  tag="${GITHUB_REF_NAME}"
  version="${tag#v}"
  if [[ "${GITHUB_REF_TYPE}" != tag ]]; then
    echo "Production releases require a stable version tag. Use dry_run for branch builds." >&2
    exit 1
  fi
fi

if [[ ! "${tag}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Expected a stable v<major>.<minor>.<patch> version." >&2
  exit 1
fi

if [[ -n "${TEST_BUILD_NUMBER:-}" ]]; then
  if [[ "${dry_run}" != true ]]; then
    echo "test_build_number is only allowed with dry_run." >&2
    exit 1
  fi
  build_number="${TEST_BUILD_NUMBER}"
else
  build_number="$(git rev-list --count HEAD)"
fi
if [[ ! "${build_number}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Expected a positive build number." >&2
  exit 1
fi

printf 'tag=%s\nversion=%s\nnumber=%s\n' "${tag}" "${version}" "${build_number}" >> "${GITHUB_OUTPUT}"
echo "Build version: ${version} (${build_number}); dry_run=${dry_run}"
