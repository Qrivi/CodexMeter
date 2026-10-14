# Releasing CodexMeter

This guide covers maintainer setup and release verification. The workflows in
[release.yml](../.github/workflows/release.yml) and
[version-tag.yml](../.github/workflows/version-tag.yml) define the release process.

## Signing and Publishing Setup

Configure these GitHub Actions repository secrets:

| Secret | Value |
| --- | --- |
| `MACOS_SIGNING_CERTIFICATE` | Base64-encoded `.p12` export of a Developer ID Application certificate, including its private key |
| `MACOS_SIGNING_PASSWORD` | Password protecting the `.p12` export |
| `APPLE_ID` | Apple Account email for notarization |
| `APPLE_PASSWORD` | Generated Apple app-specific password |
| `APPLE_TEAM_ID` | Developer team ID matching the signing certificate |
| `SPARKLE_PRIVATE_KEY` | Sparkle private-key export matching the public key embedded in the app |

Make `TAP_DISPATCH_TOKEN` available to the `notify-tap` job, which uses the
`homebrew-tap` environment. The token must allow repository dispatches to
`Qrivi/homebrew-tap`.

Set the app target's `SPARKLE_PUBLIC_ED_KEY` build setting to the public key from
Sparkle's `generate_keys` tool. Keep the private key in the macOS Keychain and the
Actions secret. Never commit keys, certificate exports, or passwords.

Enable GitHub Pages with **GitHub Actions** as its source. The `github-pages`
environment must allow deployments from `v*` tags. The workflow publishes signed
`appcast-arm64.xml` and `appcast-x86_64.xml` feeds there after both DMGs are available
on GitHub Releases.

## Publishing a Release

1. Set `MARKETING_VERSION` to an unreleased version and add release notes at
   `.github/release-notes/v<version>.md`. The version check requires a matching,
   non-empty file for PRs that change build inputs. Its contents become the GitHub
   release description.
2. Merge the release PR into `main`. Changes to app, test, project, or icon files
   trigger the version-tag workflow, which creates `v<version>` and starts Release.
   Documentation-only changes do not create a release.
3. Confirm that both architectures build, sign, notarize, and publish successfully,
   followed by the Pages deployment and Homebrew tap update.

Production tags must follow `main`'s existing history. Sparkle compares the
commit-count build number, so it must increase between releases. Preserve released
history and avoid tags from divergent branches; merge commits are supported.

To retry a release, run the Release workflow on its `v<version>` tag with `dry_run`
disabled. The latest release can be retried; older published versions are rejected
to prevent rolling back the update feeds. Retries also replace the GitHub release
description with the Markdown file from the release tag.

For the first Sparkle release, add `auto_updates true` to the CodexMeter cask in
`Qrivi/homebrew-tap`. Mention the one-time manual upgrade from 1.2.x in release notes.

## Testing a Notarized Update

Run Release manually on the branch under review with `dry_run` enabled. It performs
the production signing, notarization, and feed validation, then uploads
`test-release-*` DMGs and `test-appcast-*` feeds. It skips GitHub publication, Pages
deployment, and the Homebrew tap notification.

1. Run with `test_build_number` set to `1000`, then again with `1001`. The marketing
   version comes from the project; no release tag is required.
2. Download both runs' artifacts into separate directories. Install the older app
   in a writable test location and quit other running copies of CodexMeter.
3. Host the newer DMG and its architecture's appcast at an isolated test location.
   Change only the enclosure's download URL to the test DMG URL; preserve the
   signature, length, version, and DMG bytes. Use HTTPS for a remote host.
4. Launch the older app with `-SUFeedURL <test-appcast-url>`, then open About settings
   and choose **Check for Updates**. Verify installation, relaunch, and build `1001`.
   Test both architectures on matching hardware when available.

The feed override applies only to that launch. Keep test artifacts separate from
production feeds and remove test copies afterward: their build numbers are higher
than production builds. A successful workflow run verifies packaging; installation
and relaunch still need this separate check.

## Troubleshooting and Helper Tests

For notarization failures, inspect the `notarization-arm64` or
`notarization-x86_64` workflow artifacts. These sanitized summaries expire after
seven days. Retrieve detailed logs privately with `notarytool log` using the
submission ID; raw Apple responses are not included in workflow logs or artifacts.

When changing release helpers, run their tests locally:

```sh
python3 -m unittest discover -s .github/scripts/tests
```
