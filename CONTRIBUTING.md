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

Never commit signing keys, certificate exports, or passwords. The workflow imports
credentials into a temporary keychain and removes it even if a release fails.
For notarization failures, inspect the `notarization-arm64` or `notarization-x86_64`
workflow artifacts for Apple's submission results and available diagnostic logs.

To rerun the release workflow manually, select the intended `v<version>` tag.
The exported app version is taken from that tag.

