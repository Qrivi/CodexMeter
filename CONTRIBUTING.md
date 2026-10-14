# Contributing

Thanks for helping improve CodexMeter.

## Local Setup

1. Install Xcode and clone the repository.
2. Open `CodexMeter.xcodeproj`.
3. Run the `CodexMeter` scheme.

Add `--disable-updater` to the scheme's launch arguments when developing without
checking the production update feed.

## Development Notes

- Keep the app lightweight and native to macOS.
- Prefer small, focused SwiftUI views and plain Swift types.
- Keep user-facing copy consistent with the Codex usage dashboard where practical.
- Commit `Package.resolved` when changing dependencies; CI uses the pinned versions.
- Do not commit local Xcode user state or build artifacts.
- Follow [SECURITY.md](SECURITY.md) when handling credentials or reporting vulnerabilities.

## Validation

Before opening a pull request, run the tests from Xcode with **Product → Test**, or:

```sh
xcodebuild -project CodexMeter.xcodeproj -scheme CodexMeter -destination 'platform=macOS' test
```

Keep pull requests focused and describe the change and how you validated it.
PRs that change build inputs also need an unreleased `MARKETING_VERSION` and matching
release notes at `.github/release-notes/v<version>.md`.

## Release Maintenance

Signing setup, release steps, and notarized update testing are documented in
[the release guide](docs/RELEASING.md).
