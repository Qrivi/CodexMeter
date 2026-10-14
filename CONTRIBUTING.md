# Contributing

Thanks for helping improve CodexMeter.

## Local Setup

1. Install Xcode.
2. Clone the repository.
3. Open `CodexMeter.xcodeproj`.
4. Run the `CodexMeter` scheme.

## Development Notes

- Keep the app lightweight and native to macOS.
- Prefer small, focused SwiftUI views and plain Swift types.
- Keep user-facing copy consistent with the Codex usage dashboard where practical.
- Do not commit local Xcode user state or build artifacts.

## Validation

Before opening a pull request, run the unit tests from Xcode or with:

```sh
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter test
```

## Release signing

The release workflow archives and exports each architecture with Developer ID signing,
notarizes and staples the app and DMG, then publishes both DMGs after all checks pass.
The Homebrew tap is notified after publication.

Configure these GitHub Actions repository secrets:

| Secret | Value |
| --- | --- |
| `MACOS_SIGNING_CERTIFICATE` | Base64-encoded `.p12` export, including the private key, of a Developer ID Application certificate |
| `MACOS_SIGNING_PASSWORD` | Password protecting the `.p12` export |
| `APPLE_ID` | Apple Account email for notarization |
| `APPLE_PASSWORD` | Generated Apple app-specific password |
| `APPLE_TEAM_ID` | Developer team ID matching the signing certificate |
| `SPARKLE_PRIVATE_KEY` | Contents of the Sparkle private-key export for the public key embedded in the app |

Never commit signing keys, certificate exports, or passwords. The workflow imports
credentials into a temporary keychain and removes it even if a release fails.
For notarization failures, inspect the `notarization-arm64` or `notarization-x86_64`
workflow artifacts for summaries containing only a validated submission ID, known
status, issue severity, and numeric error codes. These summaries expire after seven
days. Raw Apple responses, free-form messages, URLs, and tool errors are neither
printed nor uploaded; they are removed when the notarization helper exits. Retrieve
detailed logs privately from Apple with `notarytool log` and the submission ID.
Signing credentials are removed before any artifact upload actions run.
The release workflow runs mocked signing and privacy tests before loading secrets.
These cover success, rejection, timeout, malformed responses, failed log downloads,
unsigned feeds, incorrect release metadata, and accidental key output.

To rerun the release workflow manually, select the intended `v<version>` tag.
The exported app version is taken from that tag. Production releases must follow
`main`'s existing history, as the version-tag workflow does. Do not cut production
tags from divergent branches or rewrite released history: Sparkle compares the
commit-count build number, which must increase between releases. Merge commits are
supported.

Production release runs are serialized across tags. Before publication, the workflow
checks all published stable release versions and rejects retries older than the
highest version. Retrying the latest release remains supported; a failed release-list
request stops publication rather than bypassing the check.

## Sparkle setup

The app uses Sparkle 2 through Swift Package Manager. Commit `Package.resolved`
alongside dependency changes; CI refuses to resolve versions outside that file.
The exported app's public key is validated before notarization.
The app owns one updater shared by the menu and
settings; Sparkle manages its update schedule and preference persistence.

`AppUpdater` selects the Apple Silicon or Intel feed for the running binary, including
Intel builds running under Rosetta. The app target's `SPARKLE_PUBLIC_ED_KEY` build
setting must contain the public key printed by Sparkle's
`generate_keys` tool. Its private key belongs in the macOS Keychain and a GitHub
Actions secret, never in the project or a build setting.

The release workflow generates each architecture's feed from the final notarized
DMG, verifies the signature and release metadata are present, and publishes the
feeds to GitHub Pages after both downloads are available on GitHub Releases. The
private key is supplied through stdin; raw tool output is removed and never uploaded.
Feeds currently advertise the latest release for each architecture; delta updates
are disabled.

Before shipping, set the `SPARKLE_PRIVATE_KEY` repository secret and enable GitHub
Pages with GitHub Actions as its source. The `github-pages` environment must allow
deployment from release tags matching `v*`. Test an update between two signed and
notarized builds before shipping this integration.

Automatic checks use Sparkle's consent prompt and daily schedule. Automatic
installation and system profiling are disabled, and downloaded updates must pass
signature validation before extraction. While an update is pending, the app appears
in the Dock so Sparkle's windows remain reachable; scheduled updates add a Dock badge.
The app returns to the menu bar when the update session ends.
Tests and previews do not start the updater. Use `--disable-updater` when launching
a development build that should not check the production feed.

## Testing a notarized update

Run the Release workflow manually on the branch under review with `dry_run` enabled.
This performs the same archive, Developer ID signing, notarization, stapling, bundle
verification, and Sparkle signing as a production release. It uploads `test-release-*`
DMGs and `test-appcast-*` feeds as workflow artifacts. It creates no GitHub release,
deploys no Pages content, and sends no Homebrew tap notification.

For a controlled update test:

1. Run a build-only job with `test_build_number` set to `1000`, then another with
   `1001`. The marketing version is read from the project; no release tag is needed.
   Production jobs always use the commit count and reject test build overrides.
2. Download both runs' artifacts into separate directories. Install the older app in
   a writable test location and quit any other running copy of CodexMeter.
3. Host the newer DMG and a copy of its architecture's appcast at an isolated test
   location. Change only the enclosure's download URL to that test DMG's URL; preserve
   the signature, length, and version. Keep the signed DMG bytes unchanged. Use HTTPS
   for a remote test host.
4. Launch the older test copy with `-SUFeedURL <test-appcast-url>`, then choose
   **Check for Updates…**. This override applies only to that launch and does not save
   a feed preference. Verify that the app installs, relaunches, and reports build
   `1001`. Check both architectures on matching hardware when available.

Keep these test files separate from the production feeds. A successful build-only
run verifies packaging; the install-and-relaunch check is still a separate step.
Remove the test copies afterward, since their build numbers are deliberately higher
than production builds.

When 1.3.0 ships, add `auto_updates true` to the Homebrew cask. Users on 1.2.x need
one Homebrew upgrade or release download to acquire Sparkle; the 1.3.0 release notes
call out this transition.
