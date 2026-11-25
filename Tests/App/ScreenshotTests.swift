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
@MainActor
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
    var safeArea = UIEdgeInsets.zero
    var scale: CGFloat = 2

    static let phone = Device(size: CGSize(width: 393, height: 852), safeArea: UIEdgeInsets(top: 59, left: 0, bottom: 34, right: 0))
    static let phoneLandscape = Device(size: CGSize(width: 852, height: 393), safeArea: UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59))
    static let smallPhone = Device(size: CGSize(width: 375, height: 667), safeArea: UIEdgeInsets(top: 20, left: 0, bottom: 0, right: 0))
    static let tabletLandscape = Device(size: CGSize(width: 1180, height: 820), safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0), scale: 1)
    static let tabletPortrait = Device(size: CGSize(width: 820, height: 1180), safeArea: UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0), scale: 1)
    static let screen = Device(size: CGSize(width: 1280, height: 720), scale: 1)
}

/// A window that reports the safe area it is told to, so a notch and a home bar are left room for
/// on whatever simulator this runs on.
private final class Stage: UIWindow {
    var safeArea = UIEdgeInsets.zero
    override var safeAreaInsets: UIEdgeInsets { safeArea }
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

@MainActor
private func shoot(_ name: String, _ device: Device, _ view: some View) async throws {
    let scene = try await activeScene()
    let window = Stage(windowScene: scene)
    window.safeArea = device.safeArea
    window.frame = CGRect(origin: .zero, size: device.size)
    window.backgroundColor = .black
    let host = UIHostingController(rootView: view)
    host.view.backgroundColor = .black
    window.rootViewController = host
    window.isHidden = false
    window.layoutIfNeeded()
    // Long enough for what animates in on appearing (the connection ring, the message card).
    try await Task.sleep(for: .milliseconds(900))

    let format = UIGraphicsImageRendererFormat()
    format.scale = device.scale
    format.opaque = true
    let bounds = CGRect(origin: .zero, size: device.size)
    let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { _ in
        window.drawHierarchy(in: bounds, afterScreenUpdates: true)
    }
    window.isHidden = true
    window.rootViewController = nil

    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let png = try #require(image.pngData())
    try png.write(to: folder.appendingPathComponent(name + ".png"))
}

#endif
