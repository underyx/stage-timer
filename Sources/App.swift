import SwiftUI
import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Analytics.setup()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting session: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if session.role == .windowExternalDisplayNonInteractive {
            return UISceneConfiguration(name: "External", sessionRole: session.role)
        }
        let wantsDisplay = options.userActivities.contains { $0.activityType == DisplaySceneDelegate.activityType }
        return UISceneConfiguration(name: wantsDisplay ? "Display" : "Control", sessionRole: session.role)
    }
}

final class ControlSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var externalDisplayRegistration: AnyObject?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let root = ControlHostingController(rootView: ControlView().environment(TimerModel.shared))
        window.rootViewController = root
        window.makeKeyAndVisible()
        self.window = window
        // Apps built with the iOS 27 SDK are no longer offered external display scenes from the
        // Info.plist role alone; the mirrored screen stays a mirror until an accessory is registered.
        if #available(iOS 27.0, *) {
            let config = UISceneConfiguration(name: "External")
            config.delegateClass = DisplaySceneDelegate.self
            externalDisplayRegistration = root.registerSceneAccessory(.externalNonInteractive(sceneConfiguration: config))
        }
        #if DEBUG
        // `-demo <seconds>`: start a countdown of that length and open a display window.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-demo"), i + 1 < args.count, let seconds = TimeInterval(args[i + 1]) {
            TimerModel.shared.setDuration(seconds)
            TimerModel.shared.message = "Wrap up"
            TimerModel.shared.showMessage = true
            TimerModel.shared.showClock = true
            TimerModel.shared.start()
            DisplaySceneDelegate.open()
        }
        #endif
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // A timer on stage must never let the iPad lock under the operator.
        UIApplication.shared.isIdleTimerDisabled = true
    }
}

/// Hosts the audience-facing timer, either on a mirrored external screen (non-interactive role)
/// or as an ordinary window the user drags onto an extended display.
final class DisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    static let activityType = "dev.bence.stagetimer.display"

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        scene.title = "Display"
        let window = UIWindow(windowScene: scene)
        window.rootViewController = FullscreenHostingController(rootView: DisplayView().environment(TimerModel.shared))
        window.makeKeyAndVisible()
        self.window = window
        let kind: DisplayKind = session.role == .windowExternalDisplayNonInteractive ? .external : .window
        TimerModel.shared.displays[session.persistentIdentifier] = kind
        Analytics.capture("display_connected", ["display": kind == .external ? "external" : "window"])
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        TimerModel.shared.displays[scene.session.persistentIdentifier] = nil
        Analytics.capture("display_disconnected")
    }

    static func open() {
        let activity = NSUserActivity(activityType: activityType)
        UIApplication.shared.requestSceneSessionActivation(nil, userActivity: activity, options: nil)
    }

    static func closeWindows() {
        for session in UIApplication.shared.openSessions
        where session.configuration.name == "Display" {
            UIApplication.shared.requestSceneSessionDestruction(session, options: nil)
        }
    }
}

/// Mid-show, a stray swipe up from the bottom edge must not drop the operator to the home screen:
/// deferring the edge makes the first swipe only reveal the home indicator.
final class ControlHostingController<Content: View>: UIHostingController<Content> {
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .bottom }
}

final class FullscreenHostingController<Content: View>: UIHostingController<Content> {
    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
}
