# Stage Screen

iPhone and iPad stage timer: the controls stay on the device, a connected display shows only the
countdown. The App Store name is **Stage Screen**; the repository, target, module and bundle id
(`dev.bence.stagetimer`, App Store Connect app 6815752916) still say Stage Timer, and the bundle
id can never change. SwiftUI on UIKit scenes, Swift 6 mode, iOS 17+, one dependency (PostHog).

README.md describes how external displays reach the app; read it before touching the scene code.

## Commands

Everything goes through the Makefile, so the laptop and CI run the same commands.

- `make test`: generate the project, build Debug for a simulator, run `Tests/` inside the app.
  `SIM="iPhone 18 Pro"` (or a UDID) picks the simulator; two runs on one simulator collide.
- `make core`: `swift test`, for the SwiftPM package at the root (`Sources/Core`, `Tests/Core`).
  No simulator, a few seconds, and it runs on Linux: a cloud session can run it before pushing.
- `make build`: Release build for a device, unsigned. It compiles what an archive would.
- `make archive`, `make upload`: the signed archive and the App Store Connect upload. Mac only.
- `make version`: the version and build that `project.yml` would upload next.

**A cloud session has no Xcode and cannot compile the app.** CI is where a change is first
compiled: push, open the pull request, and read the `CI` checks before merging. A green `core`
job alone says nothing about the app. Say so in the PR if something merged without a green `app`.

## Where the code lives

- `Sources/Core/`: the timer, with nothing of iOS in it. `TimerState` is the timer as a value
  (every transition takes `now`), `SavedState` is what a relaunch gets back, `TimerModel` is the
  observable object the views bind to. Root `Package.swift` builds this folder alone.
- `Sources/App.swift`, `Analytics.swift`, `LockKeepalive.swift`: the app around it. `App.swift`
  builds `TimerModel.shared` with the real store, PostHog and the keepalive.
- `Sources/DisplayView.swift`: what the room sees, also the monitor on the control surface.
  `Sources/ControlView.swift` lays out the operator's side from the pieces in `Sources/Views/`;
  `Sources/Theme.swift` holds its colours, its two button styles and its animation curves.
- `Tests/Core/`: the timer's behaviour, on a clock the test moves by hand. `Tests/App/`: what only
  the built app can answer (Info.plist wiring).

## CI

`.github/workflows/ci.yml` runs on every pull request and every push to main:

- `app`, on GitHub's `xcode-27` image: `make test`, then `make build`. The repository variable
  `IOS_RUNS_ON` (JSON) points it at another image or a self-hosted Mac.
- `core`, on Linux in the `swift:6.4` container: `swift test`.

The repository is private, so the `app` job's minutes bill at about ten times the Linux rate.
That is why a change that touches only `**.md` starts no run, and why a newer push cancels the
run before it. Don't add a second macOS job or a matrix without a reason worth that.

CI cannot see a real external display, AirPlay, Stage Manager or the lock button. A change to the
scene code or `LockKeepalive` is unverified until someone runs it on hardware, whatever CI says.

## Traps

- **`StageTimer.xcodeproj` and `Sources/Info.plist` are generated** by `xcodegen generate` from
  `project.yml`, and gitignored. Info.plist keys, build settings, versions and the package pin are
  edited in `project.yml` and nowhere else. A new file under `Sources/`, `Resources/` or `Tests/`
  needs no project edit, only a `make gen` before Xcode sees it.
- **It needs the iOS 27 SDK**, so Xcode 27: `ControlSceneDelegate` registers a
  `UISceneAccessory`, and an app built with that SDK gets no external-display scene without it.
  `scripts/select-xcode.sh` refuses an older Xcode in CI.
- **The tests run inside the app**, so `AppDelegate` runs first and would start PostHog with the
  real key. `make test` passes `POSTHOG_API_KEY=`, which leaves the SDK unstarted. Keep that on
  any new test command; a test run must not report a simulator as a user.
- **Every other build sends analytics, local Debug builds included.** The key is in `project.yml`
  on purpose. The PostHog project is shared with Line Bites; events carry `app=stage-timer`.
- **`Sources/Core` imports only Foundation and Observation.** One `import UIKit` or `SwiftUI` there
  and the `core` job stops compiling. Whatever the timer needs from outside comes in through
  `TimerModel.Dependencies`; tests build their own `TimerModel`, never `.shared`.
- **Every change to the timer's state goes through `TimerModel.update`.** It saves, re-derives
  `isFinished` and reschedules the wake task; a property written around it is not saved and can
  leave a countdown that never notices it ended.
- **Nothing on the control surface throws a running timer away on one tap.** Reset is held
  (`Transport`), and a new length or mode asks first once a run has started. A new control that
  calls `reset()`, `setDuration` or sets `mode` needs the same guard.
- **The control surface is always dark and never follows the system appearance** (`Theme`): it is
  used in dimmed rooms. Colours come from `Theme`, not from system colours or materials.
- **The display's digits are scaled, not re-set, to make room for a message** (`DisplayView`):
  a font size does not animate. Their size is worked out for the widest time the run will show,
  so it does not jump at 9:59; `ems` there is an estimate of SF Rounded's widths.
- **Saved state decodes all or nothing** (`SavedState`, one JSON value in UserDefaults under
  `state`). A new field in `SavedState` or `TimerState` must be optional, or the update that adds
  it silently resets every user's settings. `TimerState.Mode` raw values are stored and sent to
  analytics: don't rename them, `title` is the label.
- **A countdown with overtime off is not running once it reaches 0:00** (`isFinished`), but its
  clock is still counting underneath on purpose: turning overtime on shows how late it really is.
- **The keepalive runs whenever its setting is on and a display is connected, running timer or
  not.** Don't narrow it to "while counting": iOS may reclaim a suspended app, and the display
  showing a paused 5:00 between speakers goes with it.
- **`Tests/Core` is compiled twice**: by SwiftPM against the package module, and by Xcode into the
  hosted bundle against the app module. Its files import whichever exists (`#if canImport`).
  `Tests/App` is Xcode only and may use anything in the app.
- **Time in tests stays half a second off every boundary.** `start + 300 - start` is not exactly
  300 in floating point, and a remaining 0.0000001 s rounds up to 0:01.
- **PostHog is pinned to an exact version.** `Package.resolved` lives inside the gitignored
  `.xcodeproj`, so a version range would resolve again on every fresh checkout, CI and a release
  archive included. Raising the pin is a change like any other: its own commit, through CI.
- **macOS ships GNU make 3.81**: no `.ONESHELL`, no `.SHELLFLAGS`. A recipe that pipes xcodebuild
  into xcbeautify must set `pipefail` itself, or a failed build exits 0.

## Releasing

Merging to main and uploading a build to TestFlight are pre-approved by the owner (2026-11-25:
"feel free to merge and release to test flight"). Submitting a build to App Review still needs
his explicit word.

1. Raise `CURRENT_PROJECT_VERSION` in `project.yml` (and `MARKETING_VERSION` for a new version),
   through a pull request like any other change.
2. On the Mac, on the merged commit: `make upload`. It refuses uncommitted changes and a build
   number whose tag already exists, archives, uploads to App Store Connect, and tags the commit
   `v<version>-<build>`. `AUTH="-authenticationKeyPath … -authenticationKeyID …
   -authenticationKeyIssuerID …"` signs in with an App Store Connect API key instead of Xcode's
   account.
3. `git push origin v<version>-<build>`. The tag is the only record of which commit a build was;
   builds up to 1.0 (7) have none.

## Writing things down

Same split as the ops repository: this file is for what breaks, corrupts or wastes an hour if you
don't know it, and each entry stays short. Measurements, reasons and history go in `NOTES.md`
(create it when there is something to put there), behind a one-line pointer from here. Correct a
wrong note instead of appending to it.
