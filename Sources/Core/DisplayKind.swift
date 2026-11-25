/// A screen the audience-facing timer is being drawn on.
enum DisplayKind: String, Sendable {
    /// A physical display in mirroring mode: iPadOS hands us the whole screen.
    case external
    /// A regular app window, typically dragged onto an extended display in Stage Manager.
    case window

    /// What the audience is looking at, as analytics reports it: "external", "window" or "none".
    /// With both connected, the mirrored screen wins.
    static func audience(of displays: [String: DisplayKind]) -> String {
        let kinds = Set(displays.values)
        if kinds.contains(.external) { return DisplayKind.external.rawValue }
        if kinds.contains(.window) { return DisplayKind.window.rawValue }
        return "none"
    }
}
