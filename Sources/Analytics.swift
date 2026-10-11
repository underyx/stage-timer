import Foundation
import PostHog

/// Usage analytics. The one question worth answering is whether people actually use the
/// external display, so every timer start carries which kind of display was connected.
enum Analytics {
    /// Reads the key from Info.plist (`POSTHOG_API_KEY` in project.yml); an empty key means no
    /// SDK is started and every `capture` is a no-op, so local builds send nothing.
    static func setup() {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "PostHogAPIKey") as? String, !key.isEmpty else { return }
        let config = PostHogConfig(apiKey: key)
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.captureElementInteractions = false
        PostHogSDK.shared.setup(config)
    }

    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        PostHogSDK.shared.capture(event, properties: properties)
    }

    /// What the audience is looking at: "external" (mirrored screen), "window" (a display window,
    /// typically on an extended screen) or "none". With both, the mirrored screen wins.
    static func displayKind(_ displays: [String: DisplayKind]) -> String {
        let kinds = Set(displays.values)
        if kinds.contains(.external) { return "external" }
        if kinds.contains(.window) { return "window" }
        return "none"
    }
}
