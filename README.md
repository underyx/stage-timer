# Stage Timer

iPad timer whose controls stay on the iPad while an external display shows only the countdown.

```sh
xcodegen generate          # StageTimer.xcodeproj is generated, not committed
xcodebuild -project StageTimer.xcodeproj -scheme StageTimer -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/StageTimer.xcarchive archive -allowProvisioningUpdates
xcodebuild -exportArchive -archivePath build/StageTimer.xcarchive \
  -exportOptionsPlist scripts/export-testflight.plist -exportPath build/export -allowProvisioningUpdates
```

Bump `CURRENT_PROJECT_VERSION` in `project.yml` before each TestFlight upload.

## External displays

- **Mirrored display:** the app takes the screen over via a `windowExternalDisplayNonInteractive`
  scene. Apps built with the iOS 27 SDK only get that scene after registering a
  `UISceneAccessory.externalNonInteractive` (see `ControlSceneDelegate`); the Info.plist role alone
  leaves the screen mirrored and `UIScreen.screens` shows only the iPad.
- **Extended display (Stage Manager / Windowed Apps):** there's no dedicated scene; "Open display window"
  opens a second app window to drag onto that screen.
