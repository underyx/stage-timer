import Foundation

/// Everything worth getting back when the app is relaunched, stored as one JSON value. iOS kills
/// a backgrounded app whenever it wants the memory (the operator switching to their slides is
/// enough), and since the timer is derived from dates, putting `startedAt` back is all it takes
/// for a relaunch to show the countdown as if nothing had happened.
///
/// Two lifetimes live in here. Settings (mode, duration, amber threshold, overtime, the message
/// text, the clock) always come back. The session (the run itself, and whether the message or
/// the blackout is up) comes back only while it is plausibly the same event; see `restored(at:)`.
///
/// Decoding is all or nothing: a value this version cannot read is dropped and the app starts
/// from defaults. A field added later must be optional or it will discard everyone's settings.
struct SavedState: Codable, Equatable, Sendable {
    /// How long after the last change a session is still picked up where it was left.
    static let sessionLifetime: TimeInterval = 12 * 60 * 60

    /// When anything in here last changed. Not when the app died, which nothing can record.
    var savedAt: Date
    var timer = TimerState()
    var message = ""
    var showMessage = false
    var showClock = false
    var blackout = false

    /// What a launch at `now` should come back to: everything if the last change was within
    /// `sessionLifetime`, otherwise the settings with a fresh session. Twelve hours covers a
    /// conference day, and keeps yesterday's forgotten run from greeting the next morning as
    /// +14:00:00 in red. A save from the future (the device clock was moved back) is as
    /// untrustworthy as an old one.
    func restored(at now: Date) -> SavedState {
        let age = now.timeIntervalSince(savedAt)
        if age >= -60 && age <= Self.sessionLifetime { return self }
        var fresh = self
        fresh.timer.reset()
        fresh.showMessage = false
        fresh.blackout = false
        return fresh
    }
}

/// The slice of `UserDefaults` the model uses, so tests can hand it a dictionary instead.
protocol KeyValueStore: AnyObject {
    func data(forKey defaultName: String) -> Data?
    func bool(forKey defaultName: String) -> Bool
    func set(_ value: Any?, forKey defaultName: String)
}

extension UserDefaults: KeyValueStore {}
