# ROADPRINT — iPhone release project (Flutter, no Expo)

This is an **iOS-build-prepared source project**, not a signed IPA or App Store release. The existing Flutter app includes Explore (OpenStreetMap), Home, Trips, Stats, Memories, manual trip logging, local storage, and **foreground-only** GPS recording. No automatic background recording, Apple Maps, road matching, road-completion percentages, cloud sync, or verified production release is included.

## Simple Windows workspace
1. Extract this folder. Open it in VS Code with **File > Open Folder**.
2. Keep using `SETUP_WINDOWS.bat` and `RUN_WINDOWS.bat` for browser previews. Windows cannot compile an iOS IPA.
3. Your older local browser data may not automatically transfer to a native iPhone installation; each device has separate storage.

## Build iOS on a cloud Mac or physical Mac
1. Install Flutter and Xcode on the Mac build environment. Upload/copy this whole project there.
2. Run `bash PREPARE_IOS_ON_MAC.sh`. This generates iOS platform files, sets foreground location permission in `ios/Runner/Info.plist`, and runs static analysis.
3. Open `ios/Runner.xcworkspace` in Xcode, select your Apple Developer Team and a unique Bundle Identifier. Configure signing/provisioning. Do not use the example `com.roadprint` bundle ID as a final production identifier.
4. Test on a **physical iPhone**, especially location permissions, foreground GPS, map tiles, and persistence. Do not operate the app while driving.
5. For distribution, run `flutter build ipa --release` on macOS with valid signing. Upload to App Store Connect / TestFlight, complete privacy declarations, screenshots, and Apple review requirements.

## Optional remote compile check
The included `.github/workflows/ios-check.yml` uses a hosted macOS runner to attempt an **unsigned** iOS compile. This is a compile check, **not an installable IPA**. GitHub Actions may incur usage charges. Requires uploading the project to a GitHub repository. Build failures must be fixed before signing or shipping.

## Caveats
- Initial package downloads, hosted builds, and map tiles require internet.
- Background GPS is intentionally **not enabled**; location recording works only while ROADPRINT is active.
- GPS distance estimates are not road-network-matched and may have errors.
- OpenStreetMap public tiles are not guaranteed for production-scale use; choose a compliant tile provider before wide release.
- This project has not been compiled or tested in this environment. No claim of App Store readiness is made.


## October 10: minimalist brand pass
- Applied ROADPRINT Midnight (#0B1424), Slate (#17283F), Route Blue (#4D93F7), and Cloud (#F8FAFC) to the existing Flutter UI.
- Updated the top-bar product line to “NAVIGATE · EXPLORE · CONNECT” and refined wordmark spacing.
- This is a styling pass on the working-source prototype, **not** implementation of turn-by-turn navigation, Crews, background location, or CarPlay.
- **2 PM checkpoint:** Run `SETUP_WINDOWS.bat` (first time) and `RUN_WINDOWS.bat` from this folder; verify recording, map tiles, and local trip persistence. Flutter and dependencies must already be installed or downloaded.
