import Foundation
import PostHog

/// Usage analytics. The one question worth answering is whether people actually use the
/// external display, so every timer start carries which kind of display was connected.
/// The PostHog project is shared with Line Bites; the `app` super property tells them apart.
enum Analytics {
    /// Reads the key from Info.plist. It is set as `POSTHOG_API_KEY` in project.yml, so every
    /// build sends, local ones included; an empty key means no SDK is started and every
    /// `capture` is a no-op (`xcodebuild POSTHOG_API_KEY= …` for a build that must stay quiet).
    static func setup() {
        // Unit tests run hosted inside the app; a test run is not a person using it.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        guard let key = Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String, !key.isEmpty else { return }
        let config = PostHogConfig(apiKey: key)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = true
        config.captureElementInteractions = true
        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.register(["app": "stage-timer"])
    }

    /// The events themselves are sent by `TimerModel`, which reaches this through its
    /// dependencies; `DisplayKind.audience(of:)` names the display on each.
    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event, properties: properties)
    }
}
