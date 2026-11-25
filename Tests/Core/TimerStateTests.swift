import Foundation
import Testing
#if canImport(StageTimerCore)
@testable import StageTimerCore
#else
@testable import StageTimer
#endif

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

/// A 5:00 countdown, optionally already started at `t0`.
private func countdown(_ duration: TimeInterval = 300, overtime: Bool = true, started: Bool = false) -> TimerState {
    var timer = TimerState()
    timer.setDuration(duration)
    timer.countOvertime = overtime
    if started { timer.start(at: t0) }
    return timer
}

@Suite struct FormattingTests {
    @Test func minutesAndSeconds() {
        #expect(TimerState.format(0) == "0:00")
        #expect(TimerState.format(59) == "0:59")
        #expect(TimerState.format(300) == "5:00")
        #expect(TimerState.format(3599) == "59:59")
    }

    @Test func hoursAppearFromOneHour() {
        #expect(TimerState.format(3600) == "1:00:00")
        #expect(TimerState.format(3 * 3600 + 7 * 60 + 5) == "3:07:05")
    }

    @Test func nothingMakesItCrashOrGoNegative() {
        #expect(TimerState.format(-5) == "0:00")
        #expect(TimerState.format(TimeInterval.nan) == "0:00")
        #expect(TimerState.format(-TimeInterval.infinity) == "0:00")
        #expect(TimerState.format(TimeInterval.infinity) == "0:00")
        #expect(TimerState.format(1e300) == "99999:59:59")
    }
}

@Suite struct CountdownDisplayTests {
    @Test func freshTimerReadsItsDuration() {
        let timer = countdown()
        let shot = timer.snapshot(at: t0)
        #expect(shot == .init(text: "5:00", phase: .normal, progress: 0, overtime: nil))
        #expect(timer.isPristine)
    }

    /// The frame that draws a just-started timer carries a date slightly before the tap.
    @Test func frameDatedBeforeStartDoesNotReadFiveOhOne() {
        let timer = countdown(started: true)
        #expect(timer.snapshot(at: at(-0.04)).text == "5:00")
        #expect(timer.elapsed(at: at(-0.04)) == 0)
    }

    @Test func remainingRoundsUpSoZeroAppearsExactlyAtZero() {
        let timer = countdown(started: true)
        #expect(timer.snapshot(at: at(0.01)).text == "5:00")
        #expect(timer.snapshot(at: at(1)).text == "4:59")
        #expect(timer.snapshot(at: at(299.5)).text == "0:01")
        #expect(timer.snapshot(at: at(300)).text == "0:00")
    }

    @Test func turnsAmberAtTheThresholdAndNotBefore() {
        var timer = countdown(started: true)
        #expect(timer.snapshot(at: at(239.9)).phase == .normal)
        #expect(timer.snapshot(at: at(240)).phase == .warning)
        timer.warnAt = 0
        #expect(timer.snapshot(at: at(299)).phase == .normal)
    }

    @Test func overtimeCountsUpInRed() {
        let timer = countdown(started: true)
        let atZero = timer.snapshot(at: at(300))
        #expect(atZero.phase == .overtime)
        #expect(atZero.overtime == 0)
        #expect(timer.snapshot(at: at(300.9)).text == "0:00")
        #expect(timer.snapshot(at: at(301)).text == "+0:01")
        #expect(timer.snapshot(at: at(300 + 3725)).text == "+1:02:05")
        #expect(timer.snapshot(at: at(400)).progress == 1)
    }

    @Test func progressIsTheFractionUsed() {
        let timer = countdown(started: true)
        #expect(timer.snapshot(at: at(75)).progress == 0.25)
    }

    @Test func aZeroLengthCountdownIsAlreadyOver() {
        let shot = countdown(0).snapshot(at: t0)
        #expect(shot.text == "0:00")
        #expect(shot.phase == .overtime)
        #expect(shot.progress == 1)
    }
}

@Suite struct RunningTests {
    @Test func pauseBanksAndResumeContinues() {
        var timer = countdown()
        #expect(timer.start(at: t0) == true)
        timer.pause(at: at(10))
        #expect(!timer.isActive && !timer.isPristine)
        #expect(timer.elapsed(at: at(500)) == 10)
        #expect(timer.start(at: at(100)) == false, "resuming is not a new run")
        #expect(timer.elapsed(at: at(105)) == 15)
    }

    @Test func startWhileRunningChangesNothing() {
        var timer = countdown(started: true)
        let before = timer
        #expect(timer.start(at: at(50)) == false)
        #expect(timer == before)
    }

    @Test func resetClearsTheRunAndKeepsTheSettings() {
        var timer = countdown(120, overtime: false, started: true)
        timer.warnAt = 30
        timer.adjust(by: 60, at: at(10))
        timer.reset()
        #expect(timer.isPristine)
        #expect(timer.duration == 120 && timer.extraTime == 0 && timer.target == 120)
        #expect(timer.warnAt == 30 && timer.countOvertime == false)
    }

    @Test func changingModeStartsOverButSettingTheSameModeDoesNot() {
        var timer = countdown(started: true)
        timer.setMode(.countdown)
        #expect(timer.isActive)
        timer.setMode(.stopwatch)
        #expect(timer.isPristine && timer.mode == .stopwatch)
    }

    @Test func setDurationResets() {
        var timer = countdown(started: true)
        timer.setDuration(90)
        #expect(timer.isPristine && timer.duration == 90)
        timer.setDuration(-5)
        #expect(timer.duration == 0)
    }

    @Test func aClockMovedBackwardsNeverCountsNegativeTime() {
        var timer = countdown(started: true)
        timer.pause(at: at(-30))
        #expect(timer.elapsed(at: t0) == 0)
    }
}

@Suite struct StoppingAtZeroTests {
    @Test func stopsAtZeroAndReportsFinished() {
        let timer = countdown(overtime: false, started: true)
        #expect(!timer.isFinished(at: at(299.9)))
        #expect(timer.isFinished(at: at(300)))
        let later = timer.snapshot(at: at(1000))
        #expect(later.text == "0:00" && later.phase == .overtime && later.overtime == 0)
        #expect(timer.elapsed(at: at(1000)) == 300)
    }

    @Test func aPristineTimerIsNeverFinished() {
        #expect(!countdown(overtime: false).isFinished(at: at(1000)))
        #expect(!countdown(0, overtime: false).isFinished(at: t0))
    }

    @Test func neitherTheStopwatchNorAnOvertimeCountdownFinishes() {
        #expect(!countdown(started: true).isFinished(at: at(1000)))
        var watch = TimerState()
        watch.setMode(.stopwatch)
        watch.countOvertime = false
        watch.start(at: t0)
        #expect(!watch.isFinished(at: at(100_000)))
    }

    @Test func startOnAFinishedCountdownBeginsANewRunFromTheSetDuration() {
        var timer = countdown(overtime: false, started: true)
        timer.adjust(by: 60, at: at(10))
        #expect(timer.target == 360)
        #expect(timer.start(at: at(400)) == true)
        #expect(timer.target == 300 && timer.startedAt == at(400))
        #expect(timer.snapshot(at: at(401)).text == "4:59")
    }

    /// The overtime switch decides what is shown, never what was counted.
    @Test func turningOvertimeOnAfterTheStopShowsHowLateItReallyIs() {
        var timer = countdown(overtime: false, started: true)
        #expect(timer.snapshot(at: at(420)).text == "0:00")
        timer.countOvertime = true
        #expect(timer.snapshot(at: at(420)).text == "+2:00")
        timer.countOvertime = false
        timer.pause(at: at(430))
        timer.countOvertime = true
        #expect(timer.snapshot(at: at(999)).text == "+2:10")
    }

    @Test func addingTimeAtZeroGivesAllOfIt() {
        var running = countdown(overtime: false, started: true)
        running.adjust(by: 60, at: at(340))
        #expect(!running.isFinished(at: at(340)))
        #expect(running.snapshot(at: at(340)).text == "1:00")
        #expect(running.snapshot(at: at(370)).text == "0:30")

        // Paused 20 s after the stop: those 20 s were never shown and must not be charged.
        var paused = countdown(overtime: false, started: true)
        paused.pause(at: at(320))
        paused.adjust(by: 60, at: at(900))
        #expect(paused.snapshot(at: at(900)).text == "1:00")
    }

    @Test func shorteningBelowTheElapsedTimeFinishesIt() {
        var timer = countdown(90, overtime: false, started: true)
        timer.adjust(by: -60, at: at(45))
        #expect(timer.isFinished(at: at(45)))
        #expect(timer.snapshot(at: at(45)).text == "0:00")
        timer.adjust(by: 10, at: at(50))
        #expect(timer.snapshot(at: at(50)).text == "0:10")
    }
}

@Suite struct AdjustingTests {
    @Test func beforeTheRunItEditsTheDuration() {
        var timer = countdown()
        timer.adjust(by: 30, at: t0)
        #expect(timer.duration == 330 && timer.extraTime == 0)
        timer.adjust(by: -1000, at: t0)
        #expect(timer.duration == 0)
    }

    @Test func duringTheRunItShiftsTheRunAndResetReturnsToTheDuration() {
        var timer = countdown(started: true)
        timer.adjust(by: 60, at: at(100))
        #expect(timer.duration == 300 && timer.extraTime == 60 && timer.target == 360)
        #expect(timer.snapshot(at: at(100)).text == "4:20")
        #expect(timer.isActive, "a running timer keeps running")
        timer.reset()
        #expect(timer.snapshot(at: at(200)).text == "5:00")
    }

    @Test func aPausedRunIsStillARun() {
        var timer = countdown(started: true)
        timer.pause(at: at(10))
        timer.adjust(by: 60, at: at(20))
        #expect(timer.duration == 300 && timer.extraTime == 60)
    }

    @Test func theTargetCannotGoBelowZero() {
        var timer = countdown(60, started: true)
        timer.adjust(by: -600, at: at(10))
        #expect(timer.target == 0 && timer.extraTime == -60)
        #expect(timer.snapshot(at: at(10)).text == "+0:10")
        timer.adjust(by: 60, at: at(10))
        #expect(timer.target == 60)
    }

    @Test func shorteningPastTheElapsedTimeLandsInOvertime() {
        var timer = countdown(120, started: true)
        timer.adjust(by: -60, at: at(90))
        #expect(timer.snapshot(at: at(90)).text == "+0:30")
    }

    @Test func itDoesNothingToAStopwatch() {
        var watch = TimerState()
        watch.setMode(.stopwatch)
        let before = watch
        watch.adjust(by: 60, at: t0)
        #expect(watch == before)
    }
}

@Suite struct StopwatchTests {
    private func stopwatch(started: Bool = true) -> TimerState {
        var watch = TimerState()
        watch.setMode(.stopwatch)
        if started { watch.start(at: t0) }
        return watch
    }

    @Test func countsUpTruncatingWithNoPhaseOrProgress() {
        let shot = stopwatch().snapshot(at: at(61.9))
        #expect(shot == .init(text: "1:01", phase: .normal, progress: nil, overtime: nil))
    }

    @Test func timeAlreadySpentCanBeAddedWhileRunning() {
        var watch = stopwatch()
        watch.shiftElapsed(by: 600, at: at(5))
        #expect(watch.isActive)
        #expect(watch.snapshot(at: at(5)).text == "10:05")
        #expect(watch.snapshot(at: at(15)).text == "10:15")
    }

    @Test func timeAlreadySpentCanBeAddedBeforeStarting() {
        var watch = stopwatch(started: false)
        watch.shiftElapsed(by: 90, at: t0)
        #expect(!watch.isActive && !watch.isPristine)
        #expect(watch.snapshot(at: at(999)).text == "1:30")
        #expect(watch.start(at: at(999)) == false, "time on the clock means this resumes")
    }

    @Test func aShiftBelowZeroStopsAtZeroAndTheClockKeepsRunning() {
        var watch = stopwatch()
        watch.shiftElapsed(by: -600, at: at(40))
        #expect(watch.snapshot(at: at(40)).text == "0:00")
        #expect(watch.snapshot(at: at(45)).text == "0:05")
    }

    /// The shift applies to what the clock reads when it lands, not to when the sheet was opened.
    @Test func shiftsAddUpExactlyOnce() {
        var watch = stopwatch()
        watch.shiftElapsed(by: 60, at: at(30))
        watch.shiftElapsed(by: -10, at: at(31))
        #expect(watch.elapsed(at: at(31)) == 81)
    }
}

@Suite struct MilestonesTests {
    @Test func usedMeansEightyPercentOfARunningCountdown() {
        var timer = countdown(100, started: true)
        #expect(!timer.isUsed(at: at(79)))
        #expect(timer.isUsed(at: at(80)))
        timer.pause(at: at(90))
        #expect(!timer.isUsed(at: at(90)), "only while running")
        #expect(!countdown(0, started: true).isUsed(at: at(10)))
    }

    @Test func theStopwatchIsNeverUsed() {
        var watch = TimerState()
        watch.setMode(.stopwatch)
        watch.start(at: t0)
        #expect(!watch.isUsed(at: at(10_000)))
        #expect(watch.secondsToNextEvent(at: at(10)) == nil)
    }

    @Test func nextEventIsTheUsedMarkThenTheStopAtZero() {
        var timer = countdown(100, overtime: false, started: true)
        #expect(timer.secondsToNextEvent(at: at(30)) == 50)
        timer.markUsedReported()
        #expect(timer.secondsToNextEvent(at: at(85)) == 15)
        #expect(timer.secondsToNextEvent(at: at(100)) == nil)
    }

    @Test func nothingIsPendingWhilePausedOrOnceReportedWithOvertimeOn() {
        var timer = countdown(100, started: true)
        #expect(timer.secondsToNextEvent(at: at(10)) == 70)
        timer.markUsedReported()
        #expect(timer.secondsToNextEvent(at: at(10)) == nil)
        var paused = countdown(100)
        #expect(paused.secondsToNextEvent(at: t0) == nil)
        paused.start(at: t0)
        paused.pause(at: at(5))
        #expect(paused.secondsToNextEvent(at: at(5)) == nil)
    }

    @Test func resetForgetsTheUsedMark() {
        var timer = countdown(100, started: true)
        timer.markUsedReported()
        timer.reset()
        #expect(!timer.usedMarkReported)
    }
}
