import SwiftUI
import Testing
import UIKit
@testable import StageTimer

#if targetEnvironment(simulator)

/// Draws the real views, in the states a talk goes through, into `build/screenshots/`.
///
/// Nothing is compared, so these cannot fail on a pixel: the pictures are for whoever reviews the
/// change. Most of this app is written by cloud sessions with no simulator to look at, and CI
/// uploads the folder so they can see what they built. A simulator shares the Mac's disk, which
/// is how a test running inside the app can write into the checkout.
///
/// The sizes are the devices', not the simulator's: the views lay themselves out from the size
/// they are given, so an iPad is drawn in a window that large on whatever phone the tests run on.
///
/// A still cannot show a highlight sliding the wrong way, so the changes that animate are filmed
/// too: `build/screenshots/motion/` has a folder of frames for each. One at a time, because a
/// film is only as even as the main thread is free.
@MainActor
@Suite(.serialized)
struct ScreenshotTests {
    // MARK: The control surface on a phone

    @Test func phoneReady() async throws {
        try await shoot("phone-1-ready", .phone, ControlView().environment(timer()))
    }

    @Test func phoneRunning() async throws {
        let model = timer(length: 20 * 60, elapsed: 7 * 60 + 25.5) {
            $0.showClock = true
            $0.displayConnected(id: "shot", kind: .external)
        }
        try await shoot("phone-2-running", .phone, ControlView().environment(model))
    }

    @Test func phoneLastMinuteWithAMessage() async throws {
        let model = timer(elapsed: 4 * 60 + 23.5) {
            $0.message = "Wrap up"
            $0.showMessage = true
            $0.displayConnected(id: "shot", kind: .external)
        }
        try await shoot("phone-3-last-minute-message", .phone, ControlView().environment(model))
    }

    @Test func phoneOvertime() async throws {
        let model = timer(elapsed: 5 * 60 + 11.5) {
            $0.displayConnected(id: "shot", kind: .window)
        }
        try await shoot("phone-4-overtime", .phone, ControlView().environment(model))
    }

    @Test func phonePaused() async throws {
        let model = timer(length: 10 * 60, elapsed: 3 * 60 + 12.5, paused: true)
        try await shoot("phone-5-paused", .phone, ControlView().environment(model))
    }

    @Test func phoneFinishedAndBlackedOut() async throws {
        let finished = timer(length: 60, elapsed: 75) { $0.countOvertime = false }
        try await shoot("phone-6-finished", .phone, ControlView().environment(finished))
        let dark = timer(elapsed: 100.5) { $0.blackout = true }
        try await shoot("phone-7-blacked-out", .phone, ControlView().environment(dark))
    }

    @Test func phoneStopwatch() async throws {
        let model = timer(mode: .stopwatch, elapsed: 12 * 60 + 34.5)
        try await shoot("phone-8-stopwatch", .phone, ControlView().environment(model))
    }

    /// Setup is a sheet on a phone, and a test has no finger to raise it with: this is the
    /// sheet's content on the sheet's colours.
    @Test func phoneSetup() async throws {
        let panels: [(name: String, mode: TimerModel.Mode)] = [
            ("phone-9-setup-countdown", .countdown), ("phone-9-setup-stopwatch", .stopwatch),
        ]
        for (name, mode) in panels {
            let panel = ScrollView {
                SetupPanel(cardFill: Theme.raised, keyFill: Theme.lifted) { _ in }
                    .padding(16)
            }
            .background(Theme.surface)
            .foregroundStyle(Theme.text)
            .preferredColorScheme(.dark)
            try await shoot(name, .phone, panel.environment(timer(mode: mode)))
        }
    }

    /// Halfway through a hold on Reset. What says so is on the Start key, where no finger is.
    @Test func holdingReset() async throws {
        let row = Transport(holding: true)
            .padding(16)
            .frame(maxHeight: .infinity)
            .background(Theme.ground)
            .preferredColorScheme(.dark)
        try await shoot("phone-hold-to-reset", Device(size: CGSize(width: 393, height: 96)), row.environment(timer(elapsed: 30.5)))
    }

    // MARK: Other sizes

    @Test func smallPhone() async throws {
        let model = timer(elapsed: 62.5) {
            $0.message = "5 minutes left"
            $0.showMessage = true
        }
        try await shoot("small-phone-running", .smallPhone, ControlView().environment(model))
    }

    @Test func phoneOnItsSide() async throws {
        let model = timer(length: 20 * 60, elapsed: 7 * 60 + 25.5) {
            $0.displayConnected(id: "shot", kind: .external)
        }
        try await shoot("phone-landscape-running", .phoneLandscape, ControlView().environment(model))
    }

    @Test func tablet() async throws {
        let model = timer(length: 20 * 60, elapsed: 7 * 60 + 25.5) {
            $0.showClock = true
            $0.message = "5 minutes left"
            $0.displayConnected(id: "shot", kind: .external)
        }
        try await shoot("ipad-landscape-running", .tabletLandscape, ControlView().environment(model))
        try await shoot("ipad-portrait-running", .tabletPortrait, ControlView().environment(model))
        let stopwatch = timer(mode: .stopwatch, elapsed: 61.5)
        try await shoot("ipad-landscape-stopwatch", .tabletLandscape, ControlView().environment(stopwatch))
    }

    // MARK: What the room sees

    @Test func screen() async throws {
        let running = timer(length: 20 * 60, elapsed: 7 * 60 + 25.5) { $0.showClock = true }
        try await shoot("screen-1-running", .screen, DisplayView().environment(running))

        let message = timer(elapsed: 4 * 60 + 23.5) {
            $0.message = "Wrap up"
            $0.showMessage = true
        }
        try await shoot("screen-2-last-minute-message", .screen, DisplayView().environment(message))

        let over = timer(elapsed: 5 * 60 + 11.5)
        try await shoot("screen-3-overtime", .screen, DisplayView().environment(over))

        let long = timer(length: 90 * 60, elapsed: 10.5) { $0.showClock = true }
        try await shoot("screen-4-hours", .screen, DisplayView().environment(long))

        let narrow = timer(length: 20 * 60, elapsed: 7 * 60 + 25.5) {
            $0.message = "Questions"
            $0.showMessage = true
        }
        try await shoot("screen-5-four-by-three", Device(size: CGSize(width: 1024, height: 768), scale: 1), DisplayView().environment(narrow))
    }

    // MARK: How it moves

    @Test func choosingALength() async throws {
        let short = timer(length: 60)
        try await film("length-1m-to-10m", .phone, ControlView().environment(short)) { short.setDuration(10 * 60) }
        let near = timer()
        try await film("length-5m-to-3m", .phone, ControlView().environment(near)) { near.setDuration(3 * 60) }
        let far = timer()
        try await film("ipad-length-5m-to-20m", .tabletLandscape, ControlView().environment(far)) { far.setDuration(20 * 60) }
        // A custom length lights nothing in the row, so there is nowhere for the amber to come from.
        let custom = timer(length: 7 * 60 + 30)
        try await film("ipad-length-custom-to-3m", .tabletLandscape, ControlView().environment(custom)) { custom.setDuration(3 * 60) }
    }

    /// Before a start the nudge keys edit the length itself, on and off the lengths in the row.
    /// `step` is what the keys call.
    @Test func steppingTheLength() async throws {
        let off = timer()
        try await film("step-5m-plus-10s", .phone, ControlView().environment(off)) { off.step(by: 10) }
        let on = timer(length: 9 * 60)
        try await film("step-9m-plus-1min", .phone, ControlView().environment(on)) { on.step(by: 60) }
        let pad = timer()
        try await film("ipad-step-5m-plus-10s", .tabletLandscape, ControlView().environment(pad)) { pad.step(by: 10) }
        let back = timer(length: 5 * 60 + 10)
        try await film("ipad-step-back-onto-5m", .tabletLandscape, ControlView().environment(back)) { back.step(by: -10) }
    }

    @Test func blackingOut() async throws {
        let model = timer(elapsed: 30.5)
        try await film("blackout-on", .phone, ControlView().environment(model)) { model.blackout = true }
        try await film("blackout-off", .phone, ControlView().environment(model)) { model.blackout = false }
        let pad = timer(elapsed: 30.5)
        try await film("ipad-blackout-on", .tabletLandscape, ControlView().environment(pad)) { pad.blackout = true }
        let room = timer(elapsed: 30.5)
        try await film("screen-blackout-on", .screen, DisplayView().environment(room)) { room.blackout = true }
    }

    @Test func showingAMessage() async throws {
        let model = timer(elapsed: 30.5) { $0.message = "Wrap up" }
        try await film("message-on", .phone, ControlView().environment(model)) { model.showMessage = true }
        try await film("message-off", .phone, ControlView().environment(model)) { model.showMessage = false }
        let room = timer(length: 20 * 60, elapsed: 30.5) { $0.message = "5 minutes left" }
        try await film("screen-message-on", .screen, DisplayView().environment(room)) { room.showMessage = true }
        try await film("screen-message-off", .screen, DisplayView().environment(room)) { room.showMessage = false }
    }

    @Test func startingAndStopping() async throws {
        let model = timer()
        try await film("start", .phone, ControlView().environment(model)) { model.start() }
        try await film("pause", .phone, ControlView().environment(model)) { model.pause() }
        try await film("resume", .phone, ControlView().environment(model)) { model.start() }
        try await film("reset", .phone, ControlView().environment(model)) { model.reset() }
    }

    /// The two moments the display changes colour by itself. Nothing is changed by the film:
    /// the clock gets there, a second or two in. A view takes between one second and three to
    /// be put up before filming starts, so each timer is started well short of its moment.
    @Test func runningOut() async throws {
        let amber = timer(elapsed: 4 * 60 - 3.5)
        try await film("into-the-last-minute", .phone, ControlView().environment(amber), for: .seconds(6)) {}
        let red = timer(elapsed: 5 * 60 - 3.5)
        try await film("into-overtime", .phone, ControlView().environment(red), for: .seconds(6)) {}
        let room = timer(elapsed: 5 * 60 - 3.5)
        try await film("screen-into-overtime", .screen, DisplayView().environment(room), for: .seconds(6)) {}
        // 10:00 is one digit wider than the 9:59 that follows it a second after the start.
        let tens = timer(length: 10 * 60)
        try await film("screen-ten-minutes-to-nine", .screen, DisplayView().environment(tens), for: .seconds(2)) { tens.start() }
    }

    @Test func settingUp() async throws {
        let model = timer()
        try await film("display-connects", .phone, ControlView().environment(model)) {
            model.displayConnected(id: "shot", kind: .external)
        }
        try await film("mode-to-stopwatch", .phone, ControlView().environment(model)) { model.mode = .stopwatch }
        let pad = timer(elapsed: 30.5)
        try await film("ipad-clock-on", .tabletLandscape, ControlView().environment(pad)) { pad.showClock = true }
    }
}

// MARK: - A timer in a given state

private final class BlankStore: KeyValueStore {
    func data(forKey defaultName: String) -> Data? { nil }
    func bool(forKey defaultName: String) -> Bool { false }
    func set(_ value: Any?, forKey defaultName: String) {}
}

@MainActor
private final class Skew {
    var seconds: TimeInterval = 0
}

/// A timer on the real clock that saves nowhere and reports nothing. `elapsed` is how long ago it
/// was started: the views draw `snapshot(at:)` for the real time, so the run is started on a clock
/// set back by that much rather than waited for.
@MainActor
private func timer(
    mode: TimerModel.Mode = .countdown,
    length: TimeInterval = 5 * 60,
    elapsed: TimeInterval? = nil,
    paused: Bool = false,
    _ configure: (TimerModel) -> Void = { _ in }
) -> TimerModel {
    let skew = Skew()
    let model = TimerModel(.init(store: BlankStore(), now: { Date().addingTimeInterval(skew.seconds) }))
    model.mode = mode
    if mode == .countdown { model.setDuration(length) }
    configure(model)
    if let elapsed {
        skew.seconds = -elapsed
        model.start()
        skew.seconds = 0
        model.resync()
        if paused { model.pause() }
    }
    return model
}

// MARK: - Drawing

/// The window a picture is taken of: a size in points and the safe area a device has there.
private struct Device {
    var size: CGSize
    var safeArea = EdgeInsets()
    var scale: CGFloat = 2

    static let phone = Device(size: CGSize(width: 393, height: 852), safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
    static let phoneLandscape = Device(size: CGSize(width: 852, height: 393), safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59))
    static let smallPhone = Device(size: CGSize(width: 375, height: 667), safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))
    static let tabletLandscape = Device(size: CGSize(width: 1180, height: 820), safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), scale: 1)
    static let tabletPortrait = Device(size: CGSize(width: 820, height: 1180), safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), scale: 1)
    static let screen = Device(size: CGSize(width: 1280, height: 720), scale: 1)
}

private let folder = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("build/screenshots", isDirectory: true)

@MainActor
private func activeScene() async throws -> UIWindowScene {
    var scenes: [UIWindowScene] { UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene } }
    // The tests can start before the app's first scene is in front, and a scene that is not
    // draws nothing.
    for _ in 0..<100 {
        if let scene = scenes.first(where: { $0.activationState == .foregroundActive }) { return scene }
        try await Task.sleep(for: .milliseconds(100))
    }
    return try #require(scenes.first, "the app has no window scene to draw in")
}

/// How far inside its window a view is drawn. The simulator's own status bar and home bar would
/// otherwise push every size about, an iPad's and a projector's included, and blur the top of
/// whatever scrolls. So the view is drawn well inside a larger window, where no part of it is
/// under them, and is given the device's safe area instead.
private let margin: CGFloat = 120

/// Puts a view up in a window of the device's size and waits for it to settle.
@MainActor
private func mount(_ device: Device, _ view: some View) async throws -> (window: UIWindow, canvas: UIView) {
    let scene = try await activeScene()
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: CGSize(width: device.size.width + 2 * margin, height: device.size.height + 2 * margin))
    window.backgroundColor = .black
    window.overrideUserInterfaceStyle = .dark
    let root = UIViewController()
    let host = UIHostingController(rootView: view.safeAreaPadding(device.safeArea))
    host.view.backgroundColor = .black
    host.view.autoresizingMask = []
    root.addChild(host)
    root.view.addSubview(host.view)
    host.didMove(toParent: root)
    window.rootViewController = root
    window.isHidden = false
    host.view.frame = CGRect(origin: CGPoint(x: margin, y: margin), size: device.size)
    window.layoutIfNeeded()
    // Long enough for what animates in on appearing (the connection ring, the message card).
    try await Task.sleep(for: .milliseconds(900))
    return (window, host.view)
}

@MainActor
private func picture(of canvas: UIView, _ device: Device) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = device.scale
    format.opaque = true
    let bounds = CGRect(origin: .zero, size: device.size)
    canvas.frame = CGRect(origin: CGPoint(x: margin, y: margin), size: device.size)
    return UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
        canvas.drawHierarchy(in: bounds, afterScreenUpdates: true)
    }
}

@MainActor
private func strike(_ window: UIWindow) {
    window.isHidden = true
    window.rootViewController = nil
}

@MainActor
private func shoot(_ name: String, _ device: Device, _ view: some View) async throws {
    let (window, canvas) = try await mount(device, view)
    let image = picture(of: canvas, device)
    strike(window)

    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let png = try #require(image.pngData())
    try png.write(to: folder.appendingPathComponent(name + ".png"))
}

/// How much slower than life a film is taken. A frame takes the simulator in CI about an eighth
/// of a second to draw, so at full speed a third-of-a-second glide is two frames; slowed, the
/// same curve is a dozen.
private let slowdown = 4.0

/// Films a change: the view is put up, `change` is made, and a frame is kept as often as one
/// can be drawn until `length` has passed. The frames go to `motion/<name>/`, each named for the
/// milliseconds since the change (divide by `slowdown` for the app's own time), after one of
/// how it stood before.
///
/// The change is made on the model, as a key's action makes it. What a finger adds (a key going
/// down under it, a hold) is not in these, and neither is anything the system animates at its
/// own pace (a symbol redrawing, a sheet). The countdown itself keeps real time.
@MainActor
private func film(
    _ name: String,
    _ device: Device,
    _ view: some View,
    for length: Duration = .milliseconds(3200),
    _ change: @MainActor () -> Void
) async throws {
    let (window, canvas) = try await mount(device, view)
    Motion.slowdown = slowdown
    defer { Motion.slowdown = 1 }
    var frames = [(name: String, image: UIImage)]()
    frames.append(("0000-before", picture(of: canvas, device)))
    let clock = ContinuousClock()
    let start = clock.now
    change()
    while clock.now - start < length {
        // Gives the main thread back, so the next frame of the animation is worked out.
        try await Task.sleep(for: .milliseconds(12))
        let passed = (clock.now - start).components
        let milliseconds = Int(passed.seconds) * 1000 + Int(passed.attoseconds / 1_000_000_000_000_000)
        frames.append((String(format: "%04d", milliseconds), picture(of: canvas, device)))
    }
    strike(window)

    let reel = folder.appendingPathComponent("motion/" + name, isDirectory: true)
    try? FileManager.default.removeItem(at: reel)
    try FileManager.default.createDirectory(at: reel, withIntermediateDirectories: true)
    for frame in frames {
        let jpeg = try #require(frame.image.jpegData(compressionQuality: 0.85))
        try jpeg.write(to: reel.appendingPathComponent(frame.name + ".jpg"))
    }
}

#endif
