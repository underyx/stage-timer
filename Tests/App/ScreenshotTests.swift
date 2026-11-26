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

    /// A sheet is put up by the system over the whole window, so these are pictures of a window
    /// that is the simulator's screen and nothing else: whatever phone the tests run on, with
    /// its own safe area. They are here for the sheets' material and what stands on it.
    @Test func sheets() async throws {
        let length = ControlView()
            .environment(timer())
            .sheet(isPresented: .constant(true)) {
                DurationPicker(title: "Length", confirm: "Set", initial: 5 * 60) { _ in }
            }
        try await shootWindow("window-length-sheet", length)
        let elapsed = ControlView()
            .environment(timer(mode: .stopwatch, elapsed: 61.5))
            .sheet(isPresented: .constant(true)) {
                DurationPicker(title: "Adjust stopwatch", relative: true, initial: 0) { _ in }
            }
        try await shootWindow("window-elapsed-sheet", elapsed)
    }

    /// iOS 17 and 18 have no Liquid Glass and get flat keys of the same shapes. No simulator in
    /// CI runs those systems, so the same views are drawn here with the glass turned off.
    @Test func withoutGlass() async throws {
        Theme.glass = false
        defer { Theme.glass = true }
        let model = timer(length: 20 * 60, elapsed: 7 * 60 + 25.5) {
            $0.message = "5 minutes left"
            $0.displayConnected(id: "shot", kind: .external)
        }
        try await shoot("flat-phone-running", .phone, ControlView().environment(model))
        try await shoot("flat-phone-ready", .phone, ControlView().environment(timer()))
        try await shoot("flat-ipad-landscape-running", .tabletLandscape, ControlView().environment(model))
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
        try await shoot("screen-5-four-by-three", Device(size: CGSize(width: 1024, height: 768), scale: 1, glass: false), DisplayView().environment(narrow))
    }

    // MARK: The App Store's pictures

    /// The listing's screenshots, at the two sizes App Store Connect asks for (an iPhone of
    /// 6.9 inches, an iPad of 13), into `build/screenshots/store/`. They are the real views in
    /// the states worth showing, with the status bar and home indicator a screenshot would
    /// have drawn over them: a window in a test has neither.
    @Test func store() async throws {
        let running = timer(length: 20 * 60, elapsed: 7 * 60 + 25.5) {
            $0.displayConnected(id: "shot", kind: .external)
        }
        let message = timer(length: 20 * 60, elapsed: 15 * 60 + 0.5) {
            $0.message = "5 minutes left"
            $0.showMessage = true
            $0.displayConnected(id: "shot", kind: .external)
        }
        let lastMinute = timer(length: 10 * 60, elapsed: 9 * 60 + 15.5) {
            $0.message = "Wrap up"
            $0.showMessage = true
            $0.displayConnected(id: "shot", kind: .external)
        }
        let over = timer(length: 10 * 60, elapsed: 10 * 60 + 42.5) {
            $0.displayConnected(id: "shot", kind: .external)
        }
        let controls: [(name: String, model: TimerModel)] = [
            ("1-running", running), ("2-message", message), ("3-last-minute", lastMinute), ("4-overtime", over),
        ]
        for (name, model) in controls {
            try await shoot("store/iphone-" + name, .storePhone, StoreChrome(tablet: false) { ControlView() }.environment(model))
            try await shoot("store/ipad-" + name, .storeTablet, StoreChrome(tablet: true) { ControlView() }.environment(model))
        }
        // What the room sees, on the iPad's set as the listing has it today.
        try await shoot("store/ipad-5-screen", .storeTablet, DisplayView().environment(message))
    }

    // MARK: How it moves

    /// A film of a view with glass in it is of the part of the view that fits the simulator's
    /// screen (`picture`): the top of a phone unless it says otherwise. These are the bottom of a
    /// phone, for the message card, and the rows of keys under an iPad's monitor.
    private static let phoneFoot = CGRect(x: 0, y: 104, width: 393, height: 748)
    private static let tabletKeys = CGRect(x: 0, y: 430, width: 708, height: 280)

    @Test func choosingALength() async throws {
        let short = timer(length: 60)
        try await film("length-1m-to-10m", .phone, ControlView().environment(short)) { short.setDuration(10 * 60) }
        let near = timer()
        try await film("length-5m-to-3m", .phone, ControlView().environment(near)) { near.setDuration(3 * 60) }
        let far = timer()
        try await film("ipad-length-5m-to-20m", .tabletLandscape, ControlView().environment(far), part: Self.tabletKeys) { far.setDuration(20 * 60) }
        // A custom length lights nothing in the row, so there is nowhere for the amber to come from.
        let custom = timer(length: 7 * 60 + 30)
        try await film("ipad-length-custom-to-3m", .tabletLandscape, ControlView().environment(custom), part: Self.tabletKeys) { custom.setDuration(3 * 60) }
    }

    /// Before a start the nudge keys edit the length itself, on and off the lengths in the row.
    /// `step` is what the keys call.
    @Test func steppingTheLength() async throws {
        let off = timer()
        try await film("step-5m-plus-10s", .phone, ControlView().environment(off)) { off.step(by: 10) }
        let on = timer(length: 9 * 60)
        try await film("step-9m-plus-1min", .phone, ControlView().environment(on)) { on.step(by: 60) }
        let pad = timer()
        try await film("ipad-step-5m-plus-10s", .tabletLandscape, ControlView().environment(pad), part: Self.tabletKeys) { pad.step(by: 10) }
        let back = timer(length: 5 * 60 + 10)
        try await film("ipad-step-back-onto-5m", .tabletLandscape, ControlView().environment(back), part: Self.tabletKeys) { back.step(by: -10) }
    }

    @Test func blackingOut() async throws {
        let model = timer(elapsed: 30.5)
        try await film("blackout-on", .phone, ControlView().environment(model)) { model.blackout = true }
        try await film("blackout-off", .phone, ControlView().environment(model)) { model.blackout = false }
        let pad = timer(elapsed: 30.5)
        try await film("ipad-blackout-on", .tabletLandscape, ControlView().environment(pad), part: Self.tabletKeys) { pad.blackout = true }
        let room = timer(elapsed: 30.5)
        try await film("screen-blackout-on", .screen, DisplayView().environment(room)) { room.blackout = true }
    }

    @Test func showingAMessage() async throws {
        let model = timer(elapsed: 30.5) { $0.message = "Wrap up" }
        try await film("message-on", .phone, ControlView().environment(model), part: Self.phoneFoot) { model.showMessage = true }
        try await film("message-off", .phone, ControlView().environment(model), part: Self.phoneFoot) { model.showMessage = false }
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
        try await film("ipad-clock-on", Device.tabletLandscape.plain, ControlView().environment(pad)) { pad.showClock = true }
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
    /// Whether the view has Liquid Glass in it, which is only drawn truly on the simulator's
    /// own screen: such a view is drawn a screenful at a time (`picture`).
    var glass = true

    /// The same size for a view, or a film, in which the glass does not matter.
    var plain: Device {
        var device = self
        device.glass = false
        return device
    }

    static let phone = Device(size: CGSize(width: 393, height: 852), safeArea: EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0))
    static let phoneLandscape = Device(size: CGSize(width: 852, height: 393), safeArea: EdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 59))
    static let smallPhone = Device(size: CGSize(width: 375, height: 667), safeArea: EdgeInsets(top: 20, leading: 0, bottom: 0, trailing: 0))
    static let tabletLandscape = Device(size: CGSize(width: 1180, height: 820), safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), scale: 1)
    static let tabletPortrait = Device(size: CGSize(width: 820, height: 1180), safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), scale: 1)
    static let screen = Device(size: CGSize(width: 1280, height: 720), scale: 1, glass: false)
    /// 1320 x 2868, the 6.9 inch iPhone.
    static let storePhone = Device(size: CGSize(width: 440, height: 956), safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0), scale: 3)
    /// 2752 x 2064, the 13 inch iPad on its side.
    static let storeTablet = Device(size: CGSize(width: 1376, height: 1032), safeArea: EdgeInsets(top: 24, leading: 0, bottom: 20, trailing: 0), scale: 2)
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

/// How much larger than the view its window is, so that the view can be moved about in it.
private let margin: CGFloat = 120

/// How near the edge of the simulator's screen a view's glass is still trusted.
private let fringe: CGFloat = 24

/// The part of a window that is on the simulator's screen and clear of its status bar and home
/// bar. Liquid Glass is drawn from what is behind it on the screen: past the screen's edge it is
/// given the edge's last column of pixels instead, and a key there showed a band of the key
/// beside it. So a view larger than this is moved through it and drawn a part at a time.
@MainActor
private func onScreen(in window: UIWindow) -> CGRect {
    let screen = window.windowScene?.screen.bounds ?? window.bounds
    let top = max(window.safeAreaInsets.top, 24).rounded(.up)
    return CGRect(x: 0, y: top, width: screen.width.rounded(.down), height: (screen.height - top - 40).rounded(.down))
}

/// Puts a view up in a window and waits for it to settle. The view is given the device's size
/// and safe area and none of the simulator's own, so it is laid out the same wherever in the
/// window it is moved to.
@MainActor
private func mount(_ device: Device, _ view: some View) async throws -> (window: UIWindow, canvas: UIView) {
    let scene = try await activeScene()
    let window = UIWindow(windowScene: scene)
    window.frame = CGRect(origin: .zero, size: CGSize(width: device.size.width + 2 * margin, height: device.size.height + 2 * margin))
    window.backgroundColor = .black
    window.overrideUserInterfaceStyle = .dark
    let root = UIViewController()
    let host = UIHostingController(rootView: view.safeAreaPadding(device.safeArea))
    host.safeAreaRegions = []
    host.view.backgroundColor = .black
    host.view.autoresizingMask = []
    root.addChild(host)
    root.view.addSubview(host.view)
    host.didMove(toParent: root)
    window.rootViewController = root
    window.isHidden = false
    host.view.frame = CGRect(origin: onScreen(in: window).origin, size: device.size)
    window.layoutIfNeeded()
    // Long enough for what animates in on appearing (the connection ring, the message card).
    try await Task.sleep(for: .milliseconds(900))
    return (window, host.view)
}

/// The part of a view that one drawing covers when it starts at the view's top left corner: all
/// of a view that fits the stage, and otherwise the stage less the fringe.
@MainActor
private func firstPart(of canvas: UIView, _ device: Device) -> CGRect {
    guard device.glass, let window = canvas.window else { return CGRect(origin: .zero, size: device.size) }
    let stage = onScreen(in: window)
    return CGRect(
        x: 0, y: 0,
        width: device.size.width <= stage.width ? device.size.width : stage.width - fringe,
        height: device.size.height <= stage.height ? device.size.height : stage.height - fringe
    )
}

/// A picture of a view, or of `part` of it. A view with glass in it is moved so that each piece
/// of it in turn is on the stage, a fringe inside the stage's edge wherever the view goes on
/// past it, and only that piece is kept from each drawing.
@MainActor
private func picture(of canvas: UIView, _ device: Device, part: CGRect? = nil) -> UIImage {
    let format = UIGraphicsImageRendererFormat()
    format.scale = device.scale
    format.opaque = true
    let bounds = CGRect(origin: .zero, size: device.size)
    let part = part ?? bounds
    let stage = canvas.window.map { onScreen(in: $0) } ?? bounds
    return UIGraphicsImageRenderer(bounds: part, format: format).image { context in
        canvas.frame.origin = stage.origin
        guard device.glass else {
            canvas.drawHierarchy(in: bounds, afterScreenUpdates: true)
            return
        }
        var y = part.minY
        while y < part.maxY {
            let top = y == 0 ? 0 : fringe
            let height = y + stage.height - top >= bounds.maxY ? part.maxY - y : min(stage.height - top - fringe, part.maxY - y)
            var x = part.minX
            while x < part.maxX {
                let lead = x == 0 ? 0 : fringe
                let width = x + stage.width - lead >= bounds.maxX ? part.maxX - x : min(stage.width - lead - fringe, part.maxX - x)
                canvas.frame.origin = CGPoint(x: stage.minX + lead - x, y: stage.minY + top - y)
                context.cgContext.saveGState()
                context.cgContext.clip(to: CGRect(x: x, y: y, width: width, height: height))
                canvas.drawHierarchy(in: bounds, afterScreenUpdates: true)
                context.cgContext.restoreGState()
                x += width
            }
            y += height
        }
        canvas.frame.origin = stage.origin
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

    let file = folder.appendingPathComponent(name + ".png")
    try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let png = try #require(image.pngData())
    try png.write(to: file)
}

/// A picture of a whole window with `view` in it, for what the system puts up over a view.
@MainActor
private func shootWindow(_ name: String, _ view: some View) async throws {
    let scene = try await activeScene()
    let window = UIWindow(windowScene: scene)
    window.overrideUserInterfaceStyle = .dark
    window.rootViewController = UIHostingController(rootView: view)
    window.isHidden = false
    try await Task.sleep(for: .milliseconds(2000))
    let format = UIGraphicsImageRendererFormat()
    format.scale = 2
    let image = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    window.rootViewController?.dismiss(animated: false)
    strike(window)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try #require(image.pngData()).write(to: folder.appendingPathComponent(name + ".png"))
}

/// What the system draws over an app and a window in a test does not have: the status bar at
/// 9:41 and the home indicator.
private struct StoreChrome<Content: View>: View {
    var tablet: Bool
    @ViewBuilder var content: Content

    var body: some View {
        content
            // Each fills the whole window before it leaves the safe area, so that it is put
            // at the window's edge and not in the middle of what it was given.
            .overlay {
                statusBar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
            }
            .overlay {
                Capsule()
                    .fill(.white.opacity(0.9))
                    .frame(width: tablet ? 320 : 148, height: tablet ? 6 : 5)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea()
            }
            .allowsHitTesting(true)
    }

    @ViewBuilder private var statusBar: some View {
        if tablet {
            HStack(spacing: 6) {
                Text("9:41")
                Text("Tue Sep 9")
                Spacer()
                Image(systemName: "wifi")
                Text("100%")
                Image(systemName: "battery.100percent").font(.system(size: 17, weight: .regular))
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .frame(height: 24)
        } else {
            HStack(spacing: 6) {
                Text("9:41").font(.system(size: 17, weight: .semibold))
                Spacer()
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent").font(.system(size: 20, weight: .regular))
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.leading, 56)
            .padding(.trailing, 40)
            .frame(height: 24)
            .padding(.top, 21)
        }
    }
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
    part: CGRect? = nil,
    for length: Duration = .milliseconds(3200),
    _ change: @MainActor () -> Void
) async throws {
    let (window, canvas) = try await mount(device, view)
    let part = part ?? firstPart(of: canvas, device)
    Motion.slowdown = slowdown
    defer { Motion.slowdown = 1 }
    var frames = [(name: String, image: UIImage)]()
    frames.append(("0000-before", picture(of: canvas, device, part: part)))
    let clock = ContinuousClock()
    let start = clock.now
    change()
    while clock.now - start < length {
        // Gives the main thread back, so the next frame of the animation is worked out.
        try await Task.sleep(for: .milliseconds(12))
        let passed = (clock.now - start).components
        let milliseconds = Int(passed.seconds) * 1000 + Int(passed.attoseconds / 1_000_000_000_000_000)
        frames.append((String(format: "%04d", milliseconds), picture(of: canvas, device, part: part)))
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
