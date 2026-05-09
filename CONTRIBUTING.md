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

