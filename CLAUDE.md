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

**CI is also where the app is first seen.** `Tests/App/ScreenshotTests.swift` draws the real views
in the states a talk goes through into `build/screenshots/` during `make test`, and the `app` job
uploads the folder as the `screenshots` artifact. Nothing is compared; look at them after a change
to a view, and add a shot for a new state.

**A change that animates is filmed, and the film is read before it ships.** The same tests make one
change on a mounted view and keep the frames while it settles, in `build/screenshots/motion/<name>/`
(file names are milliseconds since the change, at a quarter of the app's speed and an eighth for a
view with glass in it, which takes four times as long to draw: `Motion.slowdown`).
Build 1.2 (9) went to TestFlight on stills alone, and the owner found three animation glitches in
ten minutes, each between two stills that looked right. Add a film for anything new that moves. An
animation that does not come from `Motion` (use `Motion.paced` for a one-off) is not slowed and is
over in two frames. Still unseen: what a finger adds (a key going down, the hold on Reset), what
the system animates at its own pace, and haptics.

**Liquid Glass is only drawn truly on the simulator's own screen.** It is made from what is behind
it there; past the screen's edge it is given the edge's last column of pixels, and a key showed a
band of the key beside it. The views drawn are larger than a phone's screen, so `picture` moves a
view across the screen, waits (glass that has just come onto the screen is not drawn yet: a key was
dark), and keeps a screenful from each drawing. A film is of one screenful (`part`, the top left one
unless the film says otherwise), so no frame waits for a move. A size whose monitor would be in two
pieces, which take long enough apart for the time to change between them, is drawn whole once and
only its keys again in pieces: `Device.keys` says where they are, and a key moved out of those
rectangles is drawn wrongly. A device with `glass` off is drawn in one go, as the display is.

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
- **Liquid Glass is for a key that sits straight on the ground, and only through `KeyStyle`,
  `ChipStyle` and `keyGlass`** (`Theme`). Cards, and keys on a card, stay flat fills: glass is for
  what floats over content, and Apple asks for few of them on screen. The deployment target is
  still iOS 17, so every use is behind `#available(iOS 26.0, *)` with the flat fill beside it;
  the `flat-*` screenshots draw that path (`Theme.glass` off), since no simulator in CI runs it.
- **The display's digits are scaled, not re-set, to make room for a message** (`DisplayView`):
  a font size does not animate. Their size is worked out for the widest time the run will show,
  so it does not jump at 9:59; `ems` there is an estimate of SF Rounded's widths.
- **The display's digits never animate their own place or size; only their colour fades.** They are
  a mask over the colour, with the animation taken off them, because any animation that reached
  the text when it changed (the colour fade did) made the new time slide in at an angle.
- **The display's change of colour is not left to `.animation(_:value:)`.** It arrives on a tick
  of the `TimelineView`, and with the modifier white to amber at 1:00 faded in one filmed run and
  cut in the next (cause not found; it may be the filming). `DisplayView` keeps the phase it draws
  as state and starts the fade with `withAnimation` from `onChange`. Amber to red at zero is no
  animation at all but a blend by the time past zero: an animation under the overtime pulse,
  which changes the colour every tick, sent the digits through cyan and green.
- **Words that change on a key go through `KeyTitle`, and a key's ink through `View.ink`.** Two
  titles cross-fading in one place were neither for a third of the change, so the old word leaves
  first. Ink fading along with a body that turns amber is grey on brown halfway, and an animation
  scoped to the foreground style did not stop it: the ink drawn is state, changed at a stroke once
  the body has turned far enough for it to be read (`Motion.inkHold`).
- **A control must not change size when its state does.** The Black out key has one title and
  lays out both of its icons: when it grew to say "Blacked out", its amber fill arrived outside
  the margin, and a key held at that width left no room for the line beside it.
- **The nudge keys go through `TimerModel.step`**, which disables animations for the change. They
  repeat while held and, before a start, walk the length across the row of lengths: anything that
  animates on the length would be restarted several times a second. For the same reason a length
  that is not in the row lights nothing there: the key at the far end used to light for it, and
  stepping threw the highlight to that end and back.
- **Saved state decodes all or nothing** (`SavedState`, one JSON value in UserDefaults under
  `state`). A new field in `SavedState` or `TimerState` must be optional, or the update that adds
  it silently resets every user's settings. `TimerState.Mode` raw values are stored and sent to
  analytics: don't rename them, `title` is the label.
- **A countdown with overtime off is not running once it reaches 0:00** (`isFinished`), but its
  clock is still counting underneath on purpose: turning overtime on shows how late it really is.
- **Once shipped, the keepalive runs whenever its setting is on and a display is connected,
  running timer or not.** Don't narrow it to "while counting": iOS may reclaim a suspended app,
  and the display showing a paused 5:00 between speakers goes with it.
- **`Tests/Core` is compiled twice**: by SwiftPM against the package module, and by Xcode into the
  hosted bundle against the app module. Its files import whichever exists (`#if canImport`).
  `Tests/App` is Xcode only and may use anything in the app.
- **Time in tests stays half a second off every boundary.** `start + 300 - start` is not exactly
  300 in floating point, and a remaining 0.0000001 s rounds up to 0:01.
- **"Keep running when locked" is in the code but not in the app.** `LockKeepalive.isAvailable`
  is false and `project.yml` declares no `UIBackgroundModes`: the owner wants an update through
  App Review before the one that adds background audio (2026-11-25). Turning it on is both edits
  in one change, its own release, and unverified until run on hardware with a display. A hosted
  test (`Tests/App/AppTests.swift`) fails if only one of the two is changed.
- **PostHog is pinned to an exact version.** `Package.resolved` lives inside the gitignored
  `.xcodeproj`, so a version range would resolve again on every fresh checkout, CI and a release
  archive included. Raising the pin is a change like any other: its own commit, through CI.
- **macOS ships GNU make 3.81**: no `.ONESHELL`, no `.SHELLFLAGS`. A recipe that pipes xcodebuild
  into xcbeautify must set `pipefail` itself, or a failed build exits 0.

## Releasing

Merging to main and uploading a build to TestFlight are pre-approved by the owner (2026-11-25:
"feel free to merge and release to test flight"). Submitting a build to App Review still needs
his explicit word.

The version and build live in `project.yml` (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`).
Raise the build for every upload, through a pull request like any other change: App Store Connect
refuses a build number it has seen. Then, from the merged commit on main, either:

- **From GitHub, no Mac:** run the `iOS TestFlight` workflow on main with `dry_run` off
  (`gh workflow run ios-testflight.yml -f dry_run=false`, or the GitHub tools' run-workflow call).
  It archives, signs, uploads and pushes the tag.
- **On the Mac:** `make upload`, then `git push origin v<version>-<build>`. `AUTH="…"` passes
  xcodebuild an App Store Connect API key instead of Xcode's account (see the Makefile).

Both refuse a build whose tag `v<version>-<build>` exists and both leave that tag on the commit
they uploaded. The tag is the only record of which commit a build was; builds up to 1.0 (7) have
none. If you upload any other way, push the tag by hand.

`.github/workflows/ios-testflight.yml`, with `dry_run` on (the default) or on a pull request that
changes it or `scripts/ci/`, does everything but the upload and the tag: do a dry run after
changing signing, the export options or the workflow.

- **The two paths sign differently.** The Mac signs automatically with Xcode's account
  (`scripts/export-testflight.plist`). GitHub signs manually with the profile named in
  `scripts/ci/ExportOptions.plist`, because the API key can't use cloud-managed signing;
  `scripts/ci/asc_profiles.py` creates or repairs that profile for the certificate the job holds.
- **The workflow's secrets come from the life repository's setup script**, run once by the owner
  at the Mac: `ios/scripts/setup-release.sh --hosted --repo underyx/stage-timer` in a checkout of
  underyx/life. It sets `ASC_API_KEY_P8`, `DIST_P12_BASE64`, `DIST_P12_PASSWORD` and the
  variables `ASC_KEY_ID`, `ASC_ISSUER_ID`, `IOS_RUNS_ON`. Run it again after the distribution
  certificate is renewed.
- **Signing settings on the xcodebuild line reach the PostHog package's targets too.** The
  workflow names the profile through `STAGE_PROFILE_<bundle id>` for that reason; a plain
  `PROVISIONING_PROFILE_SPECIFIER=` fails the package with "does not support provisioning
  profiles".
- **`scripts/ci/asc_profiles.py` is a copy** of the life repository's. Fix a bug in both.
- **`403 FORBIDDEN.REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED` at the profile step is Apple's, not
  the key's or the script's.** The owner has an agreement to accept at developer.apple.com/account;
  nobody else can. It took effect about eight minutes after he accepted (2026-11-25): re-run the
  failed job, don't rotate the key or repeat the setup.

## Writing things down

Same split as the ops repository: this file is for what breaks, corrupts or wastes an hour if you
don't know it, and each entry stays short. Measurements, reasons and history go in `NOTES.md`
(create it when there is something to put there), behind a one-line pointer from here. Correct a
wrong note instead of appending to it.
