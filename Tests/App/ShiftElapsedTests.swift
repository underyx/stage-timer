import Foundation
import Testing
@testable import StageTimer

/// Putting time already spent on the stopwatch: a rehearsal that started the clock ten minutes
/// late has to be able to add those minutes, running or not, without losing or doubling a second.
///
/// As in the baseline tests nothing sleeps, and instants sit half a second off every boundary.
@MainActor
struct ShiftElapsedTests {
    private func stopwatch() -> TimerModel {
        let model = TimerModel()
        model.mode = .stopwatch
        return model
    }

    @Test func stoppedStopwatchTakesTimeAndStartsFromIt() throws {
        let model = stopwatch()
        model.shiftElapsed(by: 600)
        #expect(!model.isRunning)
        #expect(!model.isPristine)
        #expect(model.snapshot(at: .now).text == "10:00")

        model.start()
        let started = try #require(model.startedAt)
        #expect(model.snapshot(at: started.addingTimeInterval(75.5)).text == "11:15")
    }

    @Test func runningStopwatchJumpsByTheShiftAndKeepsRunning() throws {
        let model = stopwatch()
        model.start()
        model.shiftElapsed(by: 600)
        #expect(model.isRunning)
        // The running stretch restarts at the shift, so times are measured from there.
        let shifted = try #require(model.startedAt)
        #expect(model.snapshot(at: shifted.addingTimeInterval(0.5)).text == "10:00")
        #expect(model.snapshot(at: shifted.addingTimeInterval(30.5)).text == "10:30")
    }

    /// The frame that renders the tap can carry a date from just before it, as on Start: it must
    /// show the shifted time, not a second less.
    @Test func frameDatedBeforeTheShiftAlreadyShowsIt() throws {
        let model = stopwatch()
        model.start()
        model.shiftElapsed(by: 600)
        let shifted = try #require(model.startedAt)
        #expect(model.snapshot(at: shifted.addingTimeInterval(-0.05)).text == "10:00")
    }

    @Test func shiftsAddUp() throws {
        let model = stopwatch()
        model.start()
        model.shiftElapsed(by: 60)
        model.shiftElapsed(by: 10)
        model.shiftElapsed(by: -10)
        model.shiftElapsed(by: 60)
        let shifted = try #require(model.startedAt)
        #expect(model.snapshot(at: shifted.addingTimeInterval(0.5)).text == "2:00")
    }

    @Test func removingMoreThanThereIsStopsAtZeroAndKeepsRunning() throws {
        let model = stopwatch()
        model.start()
        model.shiftElapsed(by: 600)
        model.shiftElapsed(by: -3600)
        #expect(model.isRunning)
        let shifted = try #require(model.startedAt)
        #expect(model.elapsed(at: shifted) == 0)
        #expect(model.snapshot(at: shifted.addingTimeInterval(5.5)).text == "0:05")
    }

    @Test func removingFromAnUntouchedStopwatchLeavesItPristine() {
        let model = stopwatch()
        model.shiftElapsed(by: -60)
        #expect(model.isPristine)
        #expect(model.snapshot(at: .now).text == "0:00")
    }

    @Test func pausedTimeSurvivesAShiftAndResetClearsIt() throws {
        let model = stopwatch()
        model.shiftElapsed(by: 90)
        model.shiftElapsed(by: -30)
        #expect(model.snapshot(at: .now).text == "1:00")
        model.reset()
        #expect(model.isPristine)
        #expect(model.snapshot(at: .now).text == "0:00")
    }
}
