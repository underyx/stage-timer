import Foundation

/// The timer as a value: its settings and its run. All the time maths lives here and takes `now`
/// as an argument, so it needs no clock, no screen and no actor, and is tested as plain data
/// (Tests/Core). `TimerModel` wraps one of these and adds everything that has side effects.
///
/// Time is derived from wall-clock dates rather than ticked, so every screen showing the timer
/// agrees, and a run survives the app being suspended or relaunched. Wall-clock on purpose: a
/// monotonic clock does not survive a relaunch.
struct TimerState: Codable, Equatable, Sendable {
    enum Mode: String, Codable, CaseIterable, Identifiable, Sendable {
        // The raw values are stored and sent to analytics; `title` is what people read.
        case countdown, stopwatch

        var id: Self { self }

        var title: String {
            switch self {
            case .countdown: "Countdown"
            case .stopwatch: "Stopwatch"
            }
        }
    }

    enum Phase: Equatable, Sendable { case normal, warning, overtime }

    /// What a screen needs to draw one frame.
    struct Snapshot: Equatable, Sendable {
        var text: String
        var phase: Phase
        /// 0...1 fraction of the countdown used; nil for the stopwatch.
        var progress: Double?
        /// Seconds since the countdown hit zero; nil before that.
        var overtime: TimeInterval?
    }

    /// The fraction of a countdown after which someone was plainly using it, not poking at the app.
    static let usedFraction = 0.8

    // MARK: Settings

    private(set) var mode: Mode = .countdown
    /// The length the countdown was set to. A run can be lengthened or shortened without
    /// changing it (`extraTime`), so Reset returns to this.
    private(set) var duration: TimeInterval = 5 * 60
    /// Seconds remaining at which the display turns amber; 0 disables it.
    var warnAt: TimeInterval = 60
    /// Keep counting up in red past zero instead of stopping at 0:00. Only changes what is shown:
    /// the time counted is kept either way, so flipping it mid-run loses nothing.
    var countOvertime = true

    // MARK: The run

    /// Time added to (or, negative, taken from) this run with the adjust buttons. Reset clears it.
    private(set) var extraTime: TimeInterval = 0
    /// When the clock last started running; nil while paused.
    private(set) var startedAt: Date?
    /// Time counted before `startedAt`.
    private(set) var banked: TimeInterval = 0
    /// Whether this run's 80% mark has been reported. Part of the run so it is reset with it.
    private(set) var usedMarkReported = false

    // MARK: Reading

    /// What this run counts down from.
    var target: TimeInterval { max(duration + extraTime, 0) }

    /// The clock is running underneath. A countdown stopped at zero is still active: see
    /// `isFinished(at:)`.
    var isActive: Bool { startedAt != nil }

    /// Nothing counted and not running: Start begins a new run.
    var isPristine: Bool { startedAt == nil && banked == 0 }

    private var stopsAtZero: Bool { mode == .countdown && !countOvertime }

    /// Time counted so far, ignoring the stop at zero.
    private func counted(at now: Date) -> TimeInterval {
        // `now` can predate `startedAt`: a frame's date is up to one tick older than the tap that
        // started the timer. Unclamped, the negative difference rounded a fresh 5:00 up to 5:01.
        banked + (startedAt.map { max(now.timeIntervalSince($0), 0) } ?? 0)
    }

    func elapsed(at now: Date) -> TimeInterval {
        let counted = counted(at: now)
        return stopsAtZero ? min(counted, target) : counted
    }

    /// A countdown that does not count overtime has reached 0:00. The clock underneath is left
    /// alone, so turning overtime on afterwards shows how late it really is.
    func isFinished(at now: Date) -> Bool {
        stopsAtZero && !isPristine && counted(at: now) >= target
    }

    /// A running countdown has passed its 80% mark.
    func isUsed(at now: Date) -> Bool {
        mode == .countdown && isActive && target > 0 && counted(at: now) >= target * Self.usedFraction
    }

    /// Seconds until the run next changes character with nobody touching it: the 80% mark (until
    /// reported) or the stop at zero. nil when nothing is pending.
    func secondsToNextEvent(at now: Date) -> TimeInterval? {
        guard mode == .countdown, isActive else { return nil }
        var marks: [TimeInterval] = []
        if !usedMarkReported, target > 0 { marks.append(target * Self.usedFraction) }
        if !countOvertime { marks.append(target) }
        let counted = counted(at: now)
        return marks.map { $0 - counted }.filter { $0 > 0 }.min()
    }

    func snapshot(at now: Date) -> Snapshot {
        let elapsed = elapsed(at: now)
        switch mode {
        case .stopwatch:
            return Snapshot(text: Self.format(elapsed), phase: .normal, progress: nil, overtime: nil)
        case .countdown:
            let remaining = target - elapsed
            let progress = target > 0 ? min(elapsed / target, 1) : 1
            if remaining > 0 {
                // Round up so a fresh 5:00 timer reads 5:00, and 0:00 appears exactly at zero.
                let phase: Phase = remaining <= warnAt ? .warning : .normal
                return Snapshot(text: Self.format(remaining.rounded(.up)), phase: phase, progress: progress, overtime: nil)
            }
            let over = -remaining
            let text = over < 1 ? Self.format(0) : "+" + Self.format(over)
            return Snapshot(text: text, phase: .overtime, progress: progress, overtime: over)
        }
    }

    // MARK: Changing

    /// Changing mode starts over; setting the mode it already has does nothing.
    mutating func setMode(_ new: Mode) {
        guard new != mode else { return }
        reset()
        mode = new
    }

    mutating func setDuration(_ seconds: TimeInterval) {
        reset()
        duration = max(seconds, 0)
    }

    /// Starts or resumes. Returns true when this began a new run rather than resuming one. A
    /// countdown sitting finished at 0:00 starts over from the set duration.
    @discardableResult
    mutating func start(at now: Date) -> Bool {
        if isFinished(at: now) { reset() }
        guard startedAt == nil else { return false }
        let fresh = banked == 0
        startedAt = now
        return fresh
    }

    mutating func pause(at now: Date) {
        guard let startedAt else { return }
        banked += max(now.timeIntervalSince(startedAt), 0)
        self.startedAt = nil
    }

    mutating func reset() {
        startedAt = nil
        banked = 0
        extraTime = 0
        usedMarkReported = false
    }

    /// Countdown only: give this run more or less time. Before anything has been counted there is
    /// no run to shift, so it edits the set duration itself. Running timers keep running; a target
    /// pushed below the elapsed time lands in overtime (or at 0:00 if overtime is off).
    mutating func adjust(by seconds: TimeInterval, at now: Date) {
        guard mode == .countdown else { return }
        if stopsAtZero {
            // Whatever ran past a stopped zero was never shown, so it must not eat into time
            // added now: +1 min at 0:00 gives a full minute, paused or not.
            banked = elapsed(at: now)
            if startedAt != nil { startedAt = now }
        }
        if isPristine {
            duration = max(duration + seconds, 0)
        } else {
            extraTime = max(extraTime + seconds, -duration)
        }
        if stopsAtZero { banked = min(banked, target) }
    }

    /// Shift the time already counted, for a clock that was started late (or early). Works
    /// mid-run: the running stretch is banked and restarted from now, so the shift lands exactly
    /// once and a shift below zero stops at 0:00 instead of leaving the clock in debt.
    mutating func shiftElapsed(by seconds: TimeInterval, at now: Date) {
        banked = max(elapsed(at: now) + seconds, 0)
        if startedAt != nil { startedAt = now }
    }

    mutating func markUsedReported() {
        usedMarkReported = true
    }

    // MARK: Formatting

    /// `m:ss`, or `h:mm:ss` from an hour up. Whole seconds, truncated.
    static func format(_ seconds: Int) -> String {
        let seconds = max(seconds, 0)
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    static func format(_ seconds: TimeInterval) -> String {
        // Int(_:) traps on NaN and on anything past Int.max; a clock should not be able to crash.
        format(seconds.isFinite ? Int(min(max(seconds, 0), 359_999_999)) : 0)
    }
}
