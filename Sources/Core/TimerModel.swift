import Foundation
import Observation

/// The one timer every scene renders: `TimerState` plus what is on the display, kept in
/// `SavedState`, and the side effects that follow from them (saving, analytics, the lock
/// keepalive, noticing the moments a running countdown changes on its own).
///
/// Everything it touches outside itself comes in through `Dependencies`, so this file builds and
/// is tested on Linux with a dictionary for a store and a variable for a clock. The app's own
/// instance is `TimerModel.shared` (App.swift).
@MainActor @Observable
final class TimerModel {
    typealias Mode = TimerState.Mode
    typealias Phase = TimerState.Phase
    typealias Snapshot = TimerState.Snapshot

    @MainActor
    struct Dependencies {
        var store: any KeyValueStore
        var now: @MainActor () -> Date = { Date() }
        var capture: @MainActor (_ event: String, _ properties: [String: Any]) -> Void = { _, _ in }
        /// Told whether the app must stay alive in the background. Called again with the same
        /// answer whenever that is worth re-asserting, so it has to be idempotent.
        var keepalive: @MainActor (_ wanted: Bool) -> Void = { _ in }
    }

    static let stateKey = "state"
    static let keepRunningKey = "keepRunningWhenLocked"

    private let deps: Dependencies

    /// Everything that is saved. Only `update` writes it, which is what keeps saving, the
    /// finished flag and the wake task from ever being forgotten after a change.
    private var state: SavedState
    private var keepRunning: Bool

    /// Connected display scenes, keyed by scene session ID.
    private(set) var displays: [String: DisplayKind] = [:]

    /// A countdown that does not count overtime has reached 0:00. Time-derived like everything
    /// else, but the controls need to be told when it happens, so it is kept as a flag and
    /// flipped by `wake` at the moment itself.
    private(set) var isFinished = false

    /// The latest moment the state changed. A frame drawn for an earlier date is drawn for this
    /// one instead, so a screen ticking slowly cannot show the instant before a change for long.
    @ObservationIgnored private var lastChange: Date
    @ObservationIgnored private var wake: Task<Void, Never>?

    init(_ deps: Dependencies) {
        self.deps = deps
        let now = deps.now()
        let saved = deps.store.data(forKey: Self.stateKey)
            .flatMap { try? JSONDecoder().decode(SavedState.self, from: $0) }
        state = saved?.restored(at: now) ?? SavedState(savedAt: now)
        keepRunning = deps.store.bool(forKey: Self.keepRunningKey)
        lastChange = now
        refresh(at: now)
    }

    // MARK: Settings

    /// Changing the mode starts over.
    var mode: Mode {
        get { state.timer.mode }
        set { update { $0.timer.setMode(newValue) } }
    }

    /// The length the countdown is set to. Change it with `setDuration`, which also resets.
    var duration: TimeInterval { state.timer.duration }

    /// Time added to or taken from the current run with `adjust(by:)`; Reset clears it.
    var extraTime: TimeInterval { state.timer.extraTime }

    /// What the current run counts down from: `duration + extraTime`.
    var target: TimeInterval { state.timer.target }

    /// Seconds remaining at which the display turns amber; 0 disables it.
    var warnAt: TimeInterval {
        get { state.timer.warnAt }
        set { update { $0.timer.warnAt = newValue } }
    }

    /// Keep counting up in red past zero instead of stopping at 0:00.
    var countOvertime: Bool {
        get { state.timer.countOvertime }
        set { update { $0.timer.countOvertime = newValue } }
    }

    /// Keep counting on a connected display after the top button locks the device. It is a
    /// decision about the room's hardware, not about one show, so it has no session lifetime.
    var keepRunningWhenLocked: Bool {
        get { keepRunning }
        set {
            guard newValue != keepRunning else { return }
            keepRunning = newValue
            deps.store.set(newValue, forKey: Self.keepRunningKey)
            updateKeepalive()
        }
    }

    // MARK: What the display shows

    /// The text under the timer. Editing it never puts it on the display; `showMessage` does.
    /// Clearing it takes it off, so the next message is not typed live in front of the audience.
    var message: String {
        get { state.message }
        set {
            update {
                $0.message = newValue
                if newValue.isEmpty { $0.showMessage = false }
            }
        }
    }

    /// Only ever true with a message to show.
    var showMessage: Bool {
        get { state.showMessage }
        set { update { $0.showMessage = newValue && !$0.message.isEmpty } }
    }

    var showClock: Bool {
        get { state.showClock }
        set { update { $0.showClock = newValue } }
    }

    var blackout: Bool {
        get { state.blackout }
        set { update { $0.blackout = newValue } }
    }

    // MARK: The run

    /// Counting, as the operator means it: false once a countdown has stopped at 0:00.
    var isRunning: Bool { state.timer.isActive && !isFinished }

    /// Nothing counted and not running.
    var isPristine: Bool { state.timer.isPristine }

    func elapsed(at date: Date) -> TimeInterval {
        state.timer.elapsed(at: max(date, lastChange))
    }

    func snapshot(at date: Date) -> Snapshot {
        state.timer.snapshot(at: max(date, lastChange))
    }

    /// How often a screen showing this timer has anything new to draw: every frame while it
    /// runs, once a second for the clock alone, otherwise only when something changes (which
    /// Observation reports by itself).
    var tickInterval: TimeInterval {
        if isRunning { return 0.05 }
        return state.showClock && !state.blackout ? 1 : 60
    }

    func toggle() {
        // Asked of the state rather than of `isFinished`, which is only as fresh as the last wake.
        let now = deps.now()
        if state.timer.isActive && !state.timer.isFinished(at: now) { pause() } else { start() }
    }

    /// Starts or resumes; a countdown finished at 0:00 starts over from the set duration.
    func start() {
        let now = deps.now()
        var fresh = false
        update(at: now) { fresh = $0.timer.start(at: now) }
        guard fresh else { return }
        deps.capture("timer_started", [
            "display": DisplayKind.audience(of: displays),
            "mode": mode.rawValue,
            "duration_seconds": Int(target),
        ])
    }

    func pause() {
        let now = deps.now()
        update(at: now) { $0.timer.pause(at: now) }
    }

    func reset() {
        update { $0.timer.reset() }
    }

    func setDuration(_ seconds: TimeInterval) {
        update { $0.timer.setDuration(seconds) }
    }

    /// Countdown: give this run more or less time (or, before it has started, edit the duration).
    func adjust(by seconds: TimeInterval) {
        let now = deps.now()
        update(at: now) { $0.timer.adjust(by: seconds, at: now) }
    }

    /// Stopwatch: shift the time already counted. A running stopwatch keeps running.
    func adjustElapsed(by seconds: TimeInterval) {
        let now = deps.now()
        update(at: now) { $0.timer.adjustElapsed(by: seconds, at: now) }
    }

    /// Stopwatch: make it read `seconds` now, running or not.
    func setElapsed(_ seconds: TimeInterval) {
        let now = deps.now()
        update(at: now) { $0.timer.setElapsed(seconds, at: now) }
    }

    // MARK: Displays

    func displayConnected(id: String, kind: DisplayKind) {
        displays[id] = kind
        deps.capture("display_connected", ["display": kind.rawValue])
        updateKeepalive()
    }

    func displayDisconnected(id: String) {
        removeDisplays([id])
    }

    /// Drop display windows whose scene session no longer exists. A window closed from the app
    /// switcher or Stage Manager while the app was in the background does not always reach
    /// `sceneDidDisconnect`; it may only be reported through `didDiscardSceneSessions`, or not at
    /// all until the sessions are compared on the next activation. Only `.window` entries are
    /// judged: a mirrored screen's scene is the system's, and it disconnects when the cable does.
    func pruneDisplays(keeping openSessions: Set<String>) {
        removeDisplays(displays.filter { $0.value == .window && !openSessions.contains($0.key) }.map(\.key))
    }

    private func removeDisplays(_ ids: [String]) {
        var removed = false
        for id in ids where displays.removeValue(forKey: id) != nil {
            removed = true
            deps.capture("display_disconnected", [:])
        }
        if removed { updateKeepalive() }
    }

    private func updateKeepalive() {
        deps.keepalive(keepRunning && !displays.isEmpty)
    }

    /// Bring everything derived back in line after time passed without this code running (the app
    /// was suspended): the finished flag, the wake task, and the keepalive, whose audio can have
    /// been interrupted without anything reporting the end of the interruption.
    func resync() {
        refresh(at: deps.now())
        updateKeepalive()
    }

    // MARK: Internals

    /// The only way `state` changes. A change that changes nothing is dropped, so nothing is
    /// saved and no view is invalidated for it.
    private func update(at now: Date? = nil, _ change: (inout SavedState) -> Void) {
        let now = now ?? deps.now()
        var next = state
        change(&next)
        guard next != state else { return }
        next.savedAt = now
        state = next
        lastChange = now
        save()
        refresh(at: now)
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        deps.store.set(data, forKey: Self.stateKey)
    }

    /// Settle what depends on the time as well as on the state, then arrange to be called again
    /// at the next moment that would change the answer.
    private func refresh(at now: Date) {
        let finished = state.timer.isFinished(at: now)
        if finished != isFinished {
            isFinished = finished
            lastChange = now
        }
        if !state.timer.usedMarkReported, state.timer.isUsed(at: now) {
            // Not a change the operator made, so it does not touch `savedAt`.
            state.timer.markUsedReported()
            save()
            deps.capture("timer_used", [
                "display": DisplayKind.audience(of: displays),
                "duration_seconds": Int(target),
            ])
        }
        wake?.cancel()
        wake = nil
        guard let delay = state.timer.secondsToNextEvent(at: now) else { return }
        wake = Task { [weak self] in
            // The sleep is on a monotonic clock and the timer on the wall clock. Should they
            // disagree, the mark is not reached yet on waking and this simply goes round again;
            // the floor keeps that from spinning.
            try? await Task.sleep(for: .seconds(max(delay, 0.01)))
            guard let self, !Task.isCancelled else { return }
            self.refresh(at: self.deps.now())
        }
    }

    // MARK: Formatting

    static func format(_ seconds: Int) -> String {
        TimerState.format(seconds)
    }
}
