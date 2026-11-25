import Foundation
import Testing
#if canImport(StageTimerCore)
@testable import StageTimerCore
#else
@testable import StageTimer
#endif

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

@Suite struct SavedStateTests {
    /// A show in progress: countdown running, shortened overtime-off settings, message up.
    private func midShow() -> SavedState {
        var state = SavedState(savedAt: t0)
        state.timer.setDuration(600)
        state.timer.warnAt = 120
        state.timer.countOvertime = false
        state.timer.start(at: t0)
        state.timer.adjust(by: 60, at: t0)
        state.timer.markUsedReported()
        state.message = "Wrap up"
        state.showMessage = true
        state.showClock = true
        state.blackout = true
        return state
    }

    @Test func survivesEncodingExactly() throws {
        let state = midShow()
        let data = try JSONEncoder().encode(state)
        #expect(try JSONDecoder().decode(SavedState.self, from: data) == state)
    }

    @Test func modeIsStoredAsItsStableKey() throws {
        var state = SavedState(savedAt: t0)
        state.timer.setMode(.stopwatch)
        let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
        #expect(json.contains("\"mode\":\"stopwatch\""))
    }

    @Test func aRecentSessionComesBackWhole() {
        let state = midShow()
        #expect(state.restored(at: t0.addingTimeInterval(5 * 60)) == state)
        #expect(state.restored(at: t0.addingTimeInterval(SavedState.sessionLifetime)) == state)
    }

    @Test func anOldSessionKeepsItsSettingsAndDropsTheRun() {
        let restored = midShow().restored(at: t0.addingTimeInterval(SavedState.sessionLifetime + 1))
        #expect(restored.timer.isPristine)
        #expect(restored.timer.extraTime == 0 && !restored.timer.usedMarkReported)
        #expect(!restored.showMessage && !restored.blackout)
        // Settings stay.
        #expect(restored.timer.duration == 600 && restored.timer.warnAt == 120)
        #expect(restored.timer.countOvertime == false)
        #expect(restored.message == "Wrap up" && restored.showClock)
    }

    @Test func aSaveFromTheFutureIsNotTrusted() {
        let state = midShow()
        #expect(state.restored(at: t0.addingTimeInterval(-30)) == state, "a little clock drift is fine")
        #expect(state.restored(at: t0.addingTimeInterval(-3600)).timer.isPristine)
    }

    @Test func aValueThisVersionCannotReadIsRefused() {
        #expect((try? JSONDecoder().decode(SavedState.self, from: Data("{}".utf8))) == nil)
        #expect((try? JSONDecoder().decode(SavedState.self, from: Data("junk".utf8))) == nil)
    }
}

@Suite struct DisplayKindTests {
    @Test func audienceNamesWhatIsConnectedWithTheMirroredScreenWinning() {
        #expect(DisplayKind.audience(of: [:]) == "none")
        #expect(DisplayKind.audience(of: ["a": .window]) == "window")
        #expect(DisplayKind.audience(of: ["a": .window, "b": .external]) == "external")
    }
}
