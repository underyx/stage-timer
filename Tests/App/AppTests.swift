import Foundation
import Testing
import UIKit
@testable import StageTimer

/// What only the built app can answer. The timer's behaviour is tested in Tests/Core, which also
/// runs in this bundle; these check the wiring that no compiler looks at, and that the app is
/// able to launch as the test host at all.
@MainActor
struct AppTests {
    /// Info.plist names the scene delegates as strings. Renaming a class compiles, and then
    /// launches to a black screen.
    @Test func everySceneConfigurationNamesADelegateThatExists() throws {
        let manifest = try #require(Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") as? [String: Any])
        let roles = try #require(manifest["UISceneConfigurations"] as? [String: [[String: Any]]])
        let configurations = roles.values.flatMap { $0 }
        let names = Set(configurations.compactMap { $0["UISceneConfigurationName"] as? String })
        #expect(names == ["Control", "Display", "External"])
        for configuration in configurations {
            let name = try #require(configuration["UISceneDelegateClassName"] as? String)
            #expect(NSClassFromString(name) != nil, "no class named \(name)")
        }
    }

    /// "Keep running when locked" needs the audio background mode, and the mode needs the option:
    /// a toggle that silently does nothing one way, a declared mode App Review finds unused the
    /// other. `LockKeepalive.isAvailable` and project.yml change together or this fails.
    @Test func theAudioBackgroundModeIsDeclaredExactlyWhenTheKeepaliveShips() {
        let modes = Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") as? [String] ?? []
        #expect(modes.contains("audio") == LockKeepalive.isAvailable)
    }

    @Test func theDisplayWindowActivityIsDeclared() {
        let types = Bundle.main.object(forInfoDictionaryKey: "NSUserActivityTypes") as? [String]
        #expect(types?.contains(DisplaySceneDelegate.activityType) == true)
    }

    /// The app's own timer, built on the real store, PostHog and the keepalive.
    @Test func theSharedTimerExistsAndIsReadable() {
        let model = TimerModel.shared
        #expect(TimerModel.Mode.allCases.contains(model.mode))
        #expect(model.snapshot(at: .now).text.contains(":"))
    }
}
