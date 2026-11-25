import Foundation
import Testing
@testable import StageTimer

/// What the timer does today, pinned down so that a change to it has to change a test on purpose.
///
/// Time is derived from dates, so nothing here sleeps: a test starts the timer, reads when it
/// started, and asks what the display would show at an instant relative to that. Instants sit
/// half a second off every boundary because `start + 300 - start` is not exactly 300 in floating
/// point, and a remaining time of 0.0000001 s rounds up to 0:01.
@MainActor
struct TimerModelBaselineTests {
    private func countdown(_ seconds: TimeInterval = 300) -> TimerModel {
        let model = TimerModel()
        model.setDuration(seconds)
        return model
    }

    /// Starts `model` and returns the instant it started at.
    private func start(_ model: TimerModel) throws -> Date {
        model.start()
        return try #require(model.startedAt)
    }

    // MARK: Formatting

    @Test func formatsMinutesAndSwitchesToHours() {
        #expect(TimerModel.format(0) == "0:00")
        #expect(TimerModel.format(59) == "0:59")
        #expect(TimerModel.format(60) == "1:00")
        #expect(TimerModel.format(3599) == "59:59")
        #expect(TimerModel.format(3600) == "1:00:00")
        #expect(TimerModel.format(3661) == "1:01:01")
    }

    // MARK: Countdown

    @Test func freshCountdownShowsItsFullDuration() {
        let model = countdown()
        let shot = model.snapshot(at: .now)
        #expect(shot.text == "5:00")
        #expect(shot.phase == .normal)
        #expect(shot.progress == 0)
        #expect(shot.overtime == nil)
        #expect(model.isPristine)
        #expect(!model.isRunning)
    }

    /// The frame that renders a tap on Start can carry a date from just before the tap. It read
    /// 5:01 on a 5:00 timer until elapsed time was clamped at zero.
    @Test func frameDatedBeforeTheStartReadsTheFullDuration() throws {
        let model = countdown()
        let started = try start(model)
        let earlier = started.addingTimeInterval(-0.05)
        #expect(model.elapsed(at: earlier) == 0)
        #expect(model.snapshot(at: earlier).text == "5:00")
    }

    @Test func remainingTimeRoundsUp() throws {
        let model = countdown()
        let started = try start(model)
        #expect(model.snapshot(at: started.addingTimeInterval(0.5)).text == "5:00")
        #expect(model.snapshot(at: started.addingTimeInterval(1.5)).text == "4:59")
        #expect(model.snapshot(at: started.addingTimeInterval(299.5)).text == "0:01")
    }

    @Test func turnsAmberAtTheWarningMark() throws {
        let model = countdown()
        model.warnAt = 60
        let started = try start(model)
        #expect(model.snapshot(at: started.addingTimeInterval(239.5)).phase == .normal)
        #expect(model.snapshot(at: started.addingTimeInterval(240.5)).phase == .warning)
        #expect(model.snapshot(at: started.addingTimeInterval(299.5)).phase == .warning)
    }

    @Test func warningAtZeroNeverTurnsAmber() throws {
        let model = countdown()
        model.warnAt = 0
        let started = try start(model)
        #expect(model.snapshot(at: started.addingTimeInterval(299.5)).phase == .normal)
    }

    @Test func countsUpInOvertimePastZero() throws {
        let model = countdown()
        let started = try start(model)

        // The first second past zero still reads 0:00, without a plus sign.
        let atZero = model.snapshot(at: started.addingTimeInterval(300.5))
        #expect(atZero.text == "0:00")
        #expect(atZero.phase == .overtime)
        #expect(atZero.progress == 1)

        let later = model.snapshot(at: started.addingTimeInterval(305.5))
        #expect(later.text == "+0:05")
        #expect(later.phase == .overtime)
        let over = try #require(later.overtime)
        #expect(abs(over - 5.5) < 0.001)
    }

    @Test func stopsAtZeroWhenOvertimeIsOff() throws {
        let model = countdown()
        model.countOvertime = false
        let started = try start(model)
        let later = started.addingTimeInterval(400)
        #expect(model.elapsed(at: later) == 300)
        let shot = model.snapshot(at: later)
        #expect(shot.text == "0:00")
        #expect(shot.phase == .overtime)
        #expect(shot.overtime == 0)
    }

    // MARK: Stopwatch

    @Test func stopwatchCountsUpWithNoProgressBar() throws {
        let model = TimerModel()
        model.mode = .stopwatch
        let started = try start(model)
        let shot = model.snapshot(at: started.addingTimeInterval(75.5))
        #expect(shot.text == "1:15")
        #expect(shot.phase == .normal)
        #expect(shot.progress == nil)
        #expect(shot.overtime == nil)
    }

    // MARK: Transport

    @Test func toggleStartsThenPauses() {
        let model = countdown()
        model.toggle()
        #expect(model.isRunning)
        #expect(!model.isPristine)
        model.toggle()
        #expect(!model.isRunning)
        #expect(model.startedAt == nil)
    }

    @Test func resetReturnsToPristine() throws {
        let model = countdown()
        _ = try start(model)
        model.reset()
        #expect(model.isPristine)
        #expect(model.snapshot(at: .now).text == "5:00")
    }

    @Test func changingTheModeResetsARunningTimer() throws {
        let model = countdown()
        _ = try start(model)
        model.mode = .stopwatch
        #expect(model.isPristine)
    }

    @Test func settingADurationResetsARunningTimer() throws {
        let model = countdown()
        _ = try start(model)
        model.setDuration(120)
        #expect(model.isPristine)
        #expect(model.duration == 120)
        #expect(model.snapshot(at: .now).text == "2:00")
    }

    // MARK: Adjusting the target

    @Test func adjustMovesTheTargetAndStopsAtZero() {
        let model = countdown()
        model.adjust(by: 60)
        #expect(model.duration == 360)
        model.adjust(by: -10)
        #expect(model.duration == 350)
        model.adjust(by: -1000)
        #expect(model.duration == 0)
        #expect(model.isPristine)
    }

    @Test func adjustLeavesARunningTimerRunning() throws {
        let model = countdown()
        let started = try start(model)
        model.adjust(by: 60)
        #expect(model.isRunning)
        #expect(model.startedAt == started)
        #expect(model.snapshot(at: started.addingTimeInterval(0.5)).text == "6:00")
    }

    /// A target pulled below the time already spent lands in overtime rather than at zero.
    @Test func targetPulledBelowElapsedTimeLandsInOvertime() throws {
        let model = countdown(120)
        let started = try start(model)
        model.adjust(by: -60)
        let shot = model.snapshot(at: started.addingTimeInterval(90.5))
        #expect(shot.phase == .overtime)
        #expect(shot.text == "+0:30")
    }

    // MARK: Displays

    @Test func pruningDropsClosedWindowsButNeverAMirroredScreen() {
        let model = TimerModel()
        model.displays = ["open": .window, "closed": .window, "screen": .external]
        model.pruneDisplays(keeping: ["open"])
        #expect(model.displays == ["open": .window, "screen": .external])
    }

    @Test func analyticsReportsTheMirroredScreenOverAWindow() {
        #expect(Analytics.displayKind([:]) == "none")
        #expect(Analytics.displayKind(["a": .window]) == "window")
        #expect(Analytics.displayKind(["a": .external]) == "external")
        #expect(Analytics.displayKind(["a": .window, "b": .external]) == "external")
    }
}
