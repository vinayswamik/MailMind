# MailMind

iOS app that connects to Gmail, runs on-device processing, and uses background modes for sync. This repository is an **iOS source showcase**: the server used for silent-push wake and device registration is **not** included.

## Requirements

- Recent Xcode (project format Xcode 14+)
- iOS 17.0+ deployment target
- Swift 5 (see project settings)

## Clone and build

1. **Info.plist** is gitignored so OAuth client IDs, Pub/Sub topic names, and backend URLs stay off GitHub.

   ```bash
   cp MailMind/Info.plist.example MailMind/Info.plist
   ```

2. Edit `MailMind/Info.plist` and replace every `YOUR_*` / `example.com` value:

   - **GIDClientID** and **CFBundleURLSchemes** — use the **same** client-id stem: `GIDClientID` is `STEM.apps.googleusercontent.com`, and the URL scheme is `com.googleusercontent.apps.STEM` ([Google Sign-In for iOS](https://developers.google.com/identity/sign-in/ios/start-integrating)).
   - **GmailPubSubTopicName** — only if you use Gmail push; otherwise use a placeholder string your code tolerates or gate that feature.
   - **PrivacyTriggerBackendURL** — your own backend base URL, or a placeholder if you only browse UI without push.

3. Open `MailMind.xcodeproj` in Xcode, select your development team, build and run.

## What is in this repo

- SwiftUI/UIKit app sources under `MailMind/`
- Unit test target `MailMindTests/`
- Xcode project and Swift Package dependencies

## What is not in this repo

- Go backend and deployment configs (`backend/` is ignored)
- Your real `MailMind/Info.plist` (keep a local copy; never commit it)

## License

See [LICENSE](LICENSE).
