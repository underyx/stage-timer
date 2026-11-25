import Observation
import SwiftUI

/// The one timer every scene renders. Time is derived from wall-clock dates rather than
/// ticked, so the iPad and the external display can never drift apart.
@MainActor @Observable
final class TimerModel {
    static let shared = TimerModel()

    enum Mode: String, CaseIterable, Identifiable {
        case countdown = "Countdown"
        case stopwatch = "Stopwatch"
        var id: Self { self }
    }

    enum Phase { case normal, warning, overtime }

    var mode: Mode = .countdown { didSet { reset() } }
    var duration: TimeInterval = 5 * 60
    /// Seconds remaining at which the display turns amber; 0 disables it.
    var warnAt: TimeInterval = 60
    /// Keep counting up in red past zero instead of stopping at 0:00.
    var countOvertime = true

    var message = ""
    var showMessage = false
    var showClock = false
    var blackout = false

    /// Connected display scenes, keyed by scene session ID.
    var displays: [String: DisplayKind] = [:] { didSet { updateKeepalive() } }

    /// Keep counting on a connected display after the top button locks the device. Persisted:
    /// it is a decision about the room's hardware, not about one show.
    var keepRunningWhenLocked = UserDefaults.standard.bool(forKey: TimerModel.keepRunningKey) {
        didSet {
            UserDefaults.standard.set(keepRunningWhenLocked, forKey: Self.keepRunningKey)
            updateKeepalive()
        }
    }
    private static let keepRunningKey = "keepRunningWhenLocked"

    private func updateKeepalive() {
        LockKeepalive.update(enabled: keepRunningWhenLocked, displayConnected: !displays.isEmpty)
    }

    /// Drop display windows whose scene session no longer exists. A window closed from the app
    /// switcher or Stage Manager while the app was in the background does not always reach
    /// `sceneDidDisconnect`; it may only be reported through `didDiscardSceneSessions`, or not at
    /// all until the sessions are compared on the next activation. Only `.window` entries are
    /// judged: a mirrored screen's scene is the system's, and it disconnects when the cable does.
    func pruneDisplays(keeping openSessions: Set<String>) {
        let stale = displays.filter { $0.value == .window && !openSessions.contains($0.key) }.keys
        for id in stale { displays[id] = nil }
    }

    private(set) var startedAt: Date?
    private var banked: TimeInterval = 0
    /// Set once a countdown has run through 80% of itself, the point at which someone was plainly
    /// using it rather than poking at the app. Reported once per countdown.
    private var usedReported = false
    private var usedTask: Task<Void, Never>?

    var isRunning: Bool { startedAt != nil }
    var isPristine: Bool { !isRunning && banked == 0 }

    func elapsed(at now: Date) -> TimeInterval {
        // `now` is the frame's TimelineView date, which can predate `startedAt` by up to one tick:
        // tapping Start re-renders with the current frame's date before the next tick arrives. A
        // negative elapsed rounded up read 5:01 for that one frame on a fresh 5:00 timer.
        let total = banked + (startedAt.map { max(now.timeIntervalSince($0), 0) } ?? 0)
        if mode == .countdown && !countOvertime { return min(total, duration) }
        return total
    }

    func toggle() { isRunning ? pause() : start() }

    func start() {
        guard !isRunning else { return }
        if mode == .countdown && !countOvertime && banked >= duration { banked = 0 }
        let fresh = banked == 0
        startedAt = .now
        if fresh {
            Analytics.capture("timer_started", [
                "display": Analytics.displayKind(displays),
                "mode": mode.rawValue.lowercased(),
                "duration_seconds": Int(duration),
            ])
        }
        scheduleUsedCheck()
    }

    func pause() {
        guard let startedAt else { return }
        banked += Date.now.timeIntervalSince(startedAt)
        self.startedAt = nil
        scheduleUsedCheck()
    }

    func reset() {
        startedAt = nil
        banked = 0
        usedReported = false
        scheduleUsedCheck()
    }

    /// Time is date-derived, not ticked, so the 80% mark is awaited rather than polled: one task
    /// per (re)start or duration change, cancelled by pause and reset.
    private func scheduleUsedCheck() {
        usedTask?.cancel()
        usedTask = nil
        guard mode == .countdown, isRunning, !usedReported, duration > 0 else { return }
        let wait = duration * 0.8 - elapsed(at: .now)
        usedTask = Task { [weak self] in
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            guard !Task.isCancelled else { return }
            self?.reportUsed()
        }
    }

    private func reportUsed() {
        guard !usedReported, mode == .countdown, isRunning, duration > 0,
              elapsed(at: .now) >= duration * 0.8 else { return }
        usedReported = true
        Analytics.capture("timer_used", [
            "display": Analytics.displayKind(displays),
            "duration_seconds": Int(duration),
        ])
    }

    func setDuration(_ seconds: TimeInterval) {
        reset()
        duration = seconds
    }

    /// Shift the countdown target. Running timers keep running; a target pushed below the
    /// elapsed time simply lands in overtime.
    func adjust(by seconds: TimeInterval) {
        if !countOvertime, let startedAt {
            banked = min(banked + Date.now.timeIntervalSince(startedAt), duration)
            self.startedAt = .now
        }
        duration = max(duration + seconds, 0)
        if !countOvertime { banked = min(banked, duration) }
        scheduleUsedCheck()
    }

    /// Shift the time already counted, for a clock that was started late (or early). Works
    /// mid-run: the running stretch is banked and restarted from now, so the shift lands exactly
    /// once and a shift below zero stops at 0:00 instead of leaving the clock in debt.
    func shiftElapsed(by seconds: TimeInterval) {
        let now = Date.now
        banked = max(elapsed(at: now) + seconds, 0)
        if isRunning { startedAt = now }
        scheduleUsedCheck()
    }

    struct Snapshot {
        var text: String
        var phase: Phase
        /// 0...1 fraction of the countdown used; nil for the stopwatch.
        var progress: Double?
        /// Seconds since the countdown hit zero; nil before that.
        var overtime: TimeInterval?
    }

    func snapshot(at now: Date) -> Snapshot {
        let elapsed = elapsed(at: now)
        switch mode {
        case .stopwatch:
            return Snapshot(text: Self.format(Int(elapsed)), phase: .normal, progress: nil, overtime: nil)
        case .countdown:
            let remaining = duration - elapsed
            let progress = duration > 0 ? min(elapsed / duration, 1) : 1
            if remaining > 0 {
                // Round up so a fresh 5:00 timer reads 5:00, and 0:00 appears exactly at zero.
                let phase: Phase = remaining <= warnAt ? .warning : .normal
                return Snapshot(text: Self.format(Int(remaining.rounded(.up))), phase: phase, progress: progress, overtime: nil)
            }
            let over = -remaining
            let text = Int(over) == 0 ? Self.format(0) : "+" + Self.format(Int(over))
            return Snapshot(text: text, phase: .overtime, progress: progress, overtime: over)
        }
    }

    static func format(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}

enum DisplayKind {
    /// A physical display in mirroring mode: iPadOS hands us the whole screen.
    case external
    /// A regular app window, typically dragged onto an extended display in Stage Manager.
    case window
}
