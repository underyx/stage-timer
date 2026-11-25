# Stage Screen

iPhone and iPad timer whose controls stay on the device while an external display shows only the
countdown. (The repository, Xcode target and bundle id keep the first name, Stage Timer.)

```sh
brew install xcodegen      # once; StageTimer.xcodeproj is generated from project.yml, not committed
make test                  # build for a simulator and run Tests/ inside the app
make build                 # Release build for a device, unsigned
make upload                # archive, upload to App Store Connect, tag the build
open StageTimer.xcodeproj  # after `make gen`
```

It needs Xcode 27. Every pull request and push to main is built and tested by
`.github/workflows/ci.yml`. CLAUDE.md has the rest: what is generated, how CI is set up, how a
release goes, and the traps.

## External displays

- **Mirrored display:** the app takes the screen over via a `windowExternalDisplayNonInteractive`
  scene. Apps built with the iOS 27 SDK only get that scene after registering a
  `UISceneAccessory.externalNonInteractive` (see `ControlSceneDelegate`); the Info.plist role alone
  leaves the screen mirrored and `UIScreen.screens` shows only the iPad.
- **Extended display (Stage Manager / Windowed Apps):** there's no dedicated scene; "Open display window"
  opens a second app window to drag onto that screen.
- **Locking the device:** the top button backgrounds the app, iOS suspends it within seconds, and the
  external display freezes on the last frame. "Keep running when locked" (off by default) keeps the
  app alive with a silent, mixed-in audio session while a display is connected (`LockKeepalive`,
  `UIBackgroundModes: audio`), so the display keeps counting. **Not in 1.1:** the option is
  written but switched off (`LockKeepalive.isAvailable`) and the background mode is not declared,
  so that update goes through App Review without it.
- **Display windows closed in the background** reach `didDiscardSceneSessions`, not
  `sceneDidDisconnect`; the control scene also prunes `displays` against `openSessions` on activation.
