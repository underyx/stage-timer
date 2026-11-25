import Foundation
import Testing
#if canImport(StageTimerCore)
@testable import StageTimerCore
#else
@testable import StageTimer
#endif

private let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)

private final class MemoryStore: KeyValueStore {
    var values: [String: Any] = [:]
    var writes = 0

    func data(forKey defaultName: String) -> Data? { values[defaultName] as? Data }
    func bool(forKey defaultName: String) -> Bool { values[defaultName] as? Bool ?? false }
    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value
        writes += 1
    }
}

/// A model on a clock the test moves by hand, recording what it sends out. `relaunch()` builds a
/// second model on the same store, as a new process would.
@MainActor
private final class Rig {
    let store = MemoryStore()
    var now = t0
    var events: [(name: String, properties: [String: Any])] = []
    var keepalive: [Bool] = []
    private(set) lazy var model = makeModel()

    func makeModel() -> TimerModel {
        TimerModel(.init(
            store: store,
            now: { [unowned self] in now },
            capture: { [unowned self] name, properties in events.append((name, properties)) },
            keepalive: { [unowned self] wanted in keepalive.append(wanted) }
        ))
    }

    func relaunch(after seconds: TimeInterval = 0) -> TimerModel {
        now += seconds
        return makeModel()
    }

    func advance(_ seconds: TimeInterval) {
        now += seconds
        model.resync()
    }

    func names() -> [String] { events.map(\.name) }
    func text() -> String { model.snapshot(at: now).text }
}

@MainActor @Suite struct TimerModelRunTests {
    @Test func startsPausesAndResumes() {
        let rig = Rig()
        #expect(rig.model.isPristine && !rig.model.isRunning)
        rig.model.toggle()
        #expect(rig.model.isRunning)
        rig.advance(10)
        rig.model.toggle()
        #expect(!rig.model.isRunning && !rig.model.isPristine)
        rig.advance(100)
        #expect(rig.text() == "4:50")
        rig.model.toggle()
        rig.advance(5)
        #expect(rig.text() == "4:45")
    }

    @Test func onlyANewRunIsReportedAsStarted() {
        let rig = Rig()
        rig.model.setDuration(90)
        rig.model.start()
        rig.advance(5)
        rig.model.pause()
        rig.model.start()
        #expect(rig.names() == ["timer_started"])
        let properties = rig.events[0].properties
        #expect(properties["display"] as? String == "none")
        #expect(properties["mode"] as? String == "countdown")
        #expect(properties["duration_seconds"] as? Int == 90)
    }

    @Test func usedIsReportedOncePerRunAtEightyPercent() {
        let rig = Rig()
        rig.model.setDuration(100)
        rig.model.start()
        rig.advance(79)
        #expect(!rig.names().contains("timer_used"))
        rig.advance(1)
        rig.advance(50)
        rig.model.pause()
        rig.model.start()
        #expect(rig.names().filter { $0 == "timer_used" }.count == 1)
        rig.model.reset()
        rig.model.start()
        rig.advance(90)
        #expect(rig.names().filter { $0 == "timer_used" }.count == 2)
    }

    @Test func aCountdownWithoutOvertimeFinishesAndTheNextStartIsANewRun() {
        let rig = Rig()
        rig.model.setDuration(60)
        rig.model.countOvertime = false
        rig.model.start()
        rig.advance(59)
        #expect(rig.model.isRunning && !rig.model.isFinished)
        rig.advance(1)
        #expect(rig.model.isFinished && !rig.model.isRunning && !rig.model.isPristine)
        rig.advance(30)
        #expect(rig.text() == "0:00")
        rig.model.toggle()
        #expect(rig.model.isRunning && !rig.model.isFinished)
        #expect(rig.text() == "1:00")
        #expect(rig.names().filter { $0 == "timer_started" }.count == 2)
    }

    /// `isFinished` is only as fresh as the last wake; the button must not depend on that.
    @Test func toggleRestartsAFinishedCountdownEvenBeforeTheFlagCatchesUp() {
        let rig = Rig()
        rig.model.setDuration(60)
        rig.model.countOvertime = false
        rig.model.start()
        rig.now += 61
        #expect(!rig.model.isFinished, "no wake has run on this hand-moved clock")
        rig.model.toggle()
        #expect(rig.model.isRunning)
        #expect(rig.text() == "1:00")
    }

    @Test func addingTimeToAFinishedCountdownSetsItRunningAgain() {
        let rig = Rig()
        rig.model.setDuration(60)
        rig.model.countOvertime = false
        rig.model.start()
        rig.advance(90)
        rig.model.adjust(by: 60)
        #expect(rig.model.isRunning && !rig.model.isFinished)
        #expect(rig.text() == "1:00")
        #expect(rig.model.duration == 60 && rig.model.extraTime == 60 && rig.model.target == 120)
    }

    @Test func changingModeOrDurationResets() {
        let rig = Rig()
        rig.model.start()
        rig.model.mode = .countdown
        #expect(rig.model.isRunning, "the mode it already has is not a change")
        rig.model.mode = .stopwatch
        #expect(rig.model.isPristine)
        rig.model.mode = .countdown
        rig.model.start()
        rig.model.setDuration(120)
        #expect(rig.model.isPristine && rig.text() == "2:00")
    }

    @Test func theStopwatchTakesTimeAlreadySpent() {
        let rig = Rig()
        rig.model.mode = .stopwatch
        rig.model.start()
        rig.advance(5)
        rig.model.shiftElapsed(by: 600)
        rig.advance(10)
        #expect(rig.text() == "10:15")
        rig.model.shiftElapsed(by: -15)
        #expect(rig.text() == "10:00")
        #expect(rig.model.isRunning)
    }

    /// A screen that ticks slowly draws a frame dated before the last change; it must not show
    /// the moment before that change.
    @Test func aFrameDatedBeforeTheLastChangeIsDrawnAsOfTheChange() {
        let rig = Rig()
        rig.model.setDuration(60)
        rig.model.countOvertime = false
        rig.model.start()
        rig.advance(60)
        #expect(rig.model.snapshot(at: t0.addingTimeInterval(59.96)).text == "0:00")
    }

    @Test func tickIntervalFollowsWhatThereIsToDraw() {
        let rig = Rig()
        #expect(rig.model.tickInterval == 60)
        rig.model.showClock = true
        #expect(rig.model.tickInterval == 1)
        rig.model.blackout = true
        #expect(rig.model.tickInterval == 60)
        rig.model.start()
        #expect(rig.model.tickInterval == 0.05)
    }
}

@MainActor @Suite struct TimerModelMessageTests {
    @Test func editingTheMessageNeverShowsIt() {
        let rig = Rig()
        rig.model.message = "Wrap up"
        #expect(!rig.model.showMessage)
        rig.model.showMessage = true
        rig.model.message = "Questions"
        #expect(rig.model.showMessage)
    }

    @Test func clearingTheMessageTakesItOffTheDisplay() {
        let rig = Rig()
        rig.model.message = "Wrap up"
        rig.model.showMessage = true
        rig.model.message = ""
        #expect(!rig.model.showMessage)
        rig.model.message = "Q"
        #expect(!rig.model.showMessage, "the next message is not typed live")
    }

    @Test func anEmptyMessageCannotBeShown() {
        let rig = Rig()
        rig.model.showMessage = true
        #expect(!rig.model.showMessage)
    }
}

@MainActor @Suite struct TimerModelPersistenceTests {
    @Test func aRunningCountdownSurvivesARelaunch() {
        let rig = Rig()
        rig.model.setDuration(600)
        rig.model.warnAt = 120
        rig.model.message = "Wrap up"
        rig.model.showMessage = true
        rig.model.showClock = true
        rig.model.start()
        rig.advance(30)
        rig.model.adjust(by: 60)

        let relaunched = rig.relaunch(after: 90)
        #expect(relaunched.isRunning)
        #expect(relaunched.snapshot(at: rig.now).text == "9:00")
        #expect(relaunched.duration == 600 && relaunched.extraTime == 60 && relaunched.warnAt == 120)
        #expect(relaunched.message == "Wrap up" && relaunched.showMessage && relaunched.showClock)
        #expect(rig.names() == ["timer_started"], "coming back is not a new start")
    }

    @Test func aPausedTimerAndAStopwatchComeBackToo() {
        let rig = Rig()
        rig.model.mode = .stopwatch
        rig.model.start()
        rig.advance(42)
        rig.model.pause()
        let relaunched = rig.relaunch(after: 3600)
        #expect(relaunched.mode == .stopwatch && !relaunched.isRunning && !relaunched.isPristine)
        #expect(relaunched.snapshot(at: rig.now).text == "0:42")
        // A paused total is not thrown away for being old.
        #expect(rig.relaunch(after: 5 * 24 * 3600).snapshot(at: rig.now).text == "0:42")
    }

    @Test func aCountdownThatEndedWhileTheAppWasGoneComesBackFinished() {
        let rig = Rig()
        rig.model.setDuration(60)
        rig.model.countOvertime = false
        rig.model.start()
        let relaunched = rig.relaunch(after: 300)
        #expect(relaunched.isFinished && !relaunched.isRunning)
        #expect(rig.names() == ["timer_started", "timer_used"])
        // And the report is not repeated by the launch after that.
        _ = rig.relaunch(after: 10)
        #expect(rig.names().filter { $0 == "timer_used" }.count == 1)
    }

    @Test func theNextDayKeepsTheSettingsAndStartsClean() {
        let rig = Rig()
        rig.model.setDuration(600)
        rig.model.countOvertime = false
        rig.model.message = "Wrap up"
        rig.model.showMessage = true
        rig.model.blackout = true
        rig.model.start()

        let nextDay = rig.relaunch(after: 20 * 3600)
        #expect(nextDay.isPristine && !nextDay.isFinished)
        #expect(nextDay.snapshot(at: rig.now).text == "10:00")
        #expect(nextDay.duration == 600 && nextDay.countOvertime == false && nextDay.message == "Wrap up")
        #expect(!nextDay.showMessage && !nextDay.blackout)
    }

    /// The same round trip through the store the app really uses.
    @Test func userDefaultsCarriesTheStateBetweenLaunches() throws {
        let suite = "stage-timer-tests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = TimerModel(.init(store: defaults, now: { t0 }))
        first.setDuration(90)
        first.message = "Wrap up"
        first.keepRunningWhenLocked = true
        first.start()

        let second = TimerModel(.init(store: defaults, now: { t0.addingTimeInterval(30) }))
        #expect(second.isRunning && second.message == "Wrap up" && second.keepRunningWhenLocked)
        #expect(second.snapshot(at: t0.addingTimeInterval(30)).text == "1:00")
    }

    @Test func unreadableSavedStateStartsFromDefaults() {
        let rig = Rig()
        rig.store.values[TimerModel.stateKey] = Data("not json".utf8)
        #expect(rig.model.isPristine && rig.model.duration == 300 && rig.model.mode == .countdown)
    }

    @Test func aChangeThatChangesNothingIsNotSaved() {
        let rig = Rig()
        rig.model.showClock = true
        let writes = rig.store.writes
        rig.model.showClock = true
        rig.model.reset()
        rig.model.pause()
        rig.model.message = ""
        #expect(rig.store.writes == writes)
    }

    @Test func keepRunningWhenLockedLivesUnderItsOwnKey() {
        let rig = Rig()
        rig.store.values[TimerModel.keepRunningKey] = true
        #expect(rig.model.keepRunningWhenLocked)
        rig.model.keepRunningWhenLocked = false
        #expect(rig.store.values[TimerModel.keepRunningKey] as? Bool == false)
        #expect(!rig.relaunch(after: 48 * 3600).keepRunningWhenLocked)
    }
}

@MainActor @Suite struct TimerModelDisplayTests {
    @Test func connectingAndDisconnectingAreReported() {
        let rig = Rig()
        rig.model.displayConnected(id: "a", kind: .external)
        rig.model.displayConnected(id: "b", kind: .window)
        rig.model.displayDisconnected(id: "a")
        rig.model.displayDisconnected(id: "never-connected")
        #expect(rig.names() == ["display_connected", "display_connected", "display_disconnected"])
        #expect(rig.events[0].properties["display"] as? String == "external")
        #expect(rig.events[1].properties["display"] as? String == "window")
        #expect(rig.model.displays == ["b": .window])
        rig.model.start()
        #expect(rig.events.last?.properties["display"] as? String == "window")
    }

    @Test func pruningDropsOnlyWindowsWhoseSessionIsGone() {
        let rig = Rig()
        rig.model.displayConnected(id: "screen", kind: .external)
        rig.model.displayConnected(id: "open", kind: .window)
        rig.model.displayConnected(id: "closed", kind: .window)
        rig.model.pruneDisplays(keeping: ["open"])
        #expect(rig.model.displays == ["screen": .external, "open": .window])
    }

    @Test func keepaliveIsWantedOnlyWithTheSettingOnAndADisplayConnected() {
        let rig = Rig()
        rig.model.displayConnected(id: "a", kind: .external)
        #expect(rig.keepalive.last == false)
        rig.model.keepRunningWhenLocked = true
        #expect(rig.keepalive.last == true)
        rig.model.displayDisconnected(id: "a")
        #expect(rig.keepalive.last == false)
    }

    @Test func resyncReassertsTheKeepalive() {
        let rig = Rig()
        rig.model.keepRunningWhenLocked = true
        rig.model.displayConnected(id: "a", kind: .window)
        let before = rig.keepalive.count
        rig.model.resync()
        #expect(rig.keepalive.count == before + 1 && rig.keepalive.last == true)
    }
}
