import SwiftUI

/// Black out, start or pause, and reset: the row a thumb rests on.
///
/// Start is in the middle with a key of the same width on either side. Reset is the one control
/// here that cannot be taken back, and it sits beside the one pressed most, so it has to be held.
/// A held key hides its own face under the finger, so the feedback for the hold is drawn on the
/// Start key next to it, which the finger never covers. Black out is taken back by a second tap.
struct Transport: View {
    @Environment(TimerModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var holding = false
    /// 0...1 of the hold, as drawn.
    @State private var fill: CGFloat = 0
    @State private var ticks = 0
    @State private var resets = 0
    @State private var ticker: Task<Void, Never>?

    private static let holdTime = 0.7
    /// The width of the key on either side of Start.
    private static let side: CGFloat = 96

    /// `holding` draws the row as it is partway through a hold on Reset. Only a screenshot asks
    /// for it: nothing but a finger can hold the key.
    init(holding: Bool = false) {
        _holding = State(initialValue: holding)
        _fill = State(initialValue: holding ? 0.6 : 0)
    }

    var body: some View {
        HStack(spacing: Theme.keyGap) {
            BlackoutKey()
                .frame(width: Self.side)

            Button { model.toggle() } label: {
                Label {
                    KeyTitle(title)
                } icon: {
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .font(.title2.weight(.bold))
            }
            .buttonStyle(model.isRunning ? KeyStyle(fill: Theme.raised) : KeyStyle.primary())
            .animation(Motion.state, value: model.isRunning)
            .overlay { holdFeedback }
            .keyboardShortcut(.space, modifiers: [])

            resetKey
                .frame(width: Self.side)
        }
        .frame(height: 64)
        // A firm click to start, a softer one to stop; the same softer one arrives by itself when
        // a countdown that stops at zero gets there.
        .sensoryFeedback(trigger: model.isRunning) { _, running in
            .impact(weight: running ? .medium : .light)
        }
        // The hold winds up under the finger, then lands.
        .sensoryFeedback(trigger: ticks) { _, tick in
            tick > 0 ? .impact(flexibility: .rigid, intensity: min(0.25 + Double(tick) * 0.1, 1)) : nil
        }
        .sensoryFeedback(.success, trigger: resets)
    }

    private var title: String {
        if model.isRunning { return "Pause" }
        if model.isPristine { return "Start" }
        return model.isFinished ? "Restart" : "Resume"
    }

    /// Covers the Start key while Reset is held: red sweeps in from the Reset side.
    private var holdFeedback: some View {
        GeometryReader { geo in
            ZStack(alignment: .trailing) {
                Theme.surface
                Theme.hold.frame(width: geo.size.width * fill)
            }
            .overlay {
                // On one line where the key is wide enough for it (an iPad), on two on a phone,
                // where the key has a key on either side of it.
                ViewThatFits(in: .horizontal) {
                    Text("Keep holding to reset")
                        .lineLimit(1)
                    Text("Keep holding\nto reset")
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                }
                .font(.headline)
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
            }
        }
        .clipShape(Capsule())
        .opacity(holding ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var resetKey: some View {
        VStack(spacing: 2) {
            Label("Reset", systemImage: "arrow.counterclockwise")
                .font(.body.weight(.semibold))
            Text("hold")
                .font(.caption2.weight(.medium))
                .foregroundStyle(holding ? Color.white : Theme.secondary)
        }
        .foregroundStyle(holding ? Color.white : Theme.text)
        // The words dim when there is nothing to reset; the key itself stays where it is.
        .opacity(model.isPristine ? 0.4 : 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .keyGlass(lit: holding ? Theme.hold : nil, fallback: Theme.raised)
        .scaleEffect(holding && !reduceMotion ? 0.95 : 1)
        .contentShape(Capsule())
        .onLongPressGesture(minimumDuration: Self.holdTime, maximumDistance: 80) {
            model.reset()
            resets += 1
        } onPressingChanged: { pressing in
            press(pressing && !model.isPristine)
        }
        .allowsHitTesting(!model.isPristine)
        .animation(Motion.state, value: model.isPristine)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Reset")
        .accessibilityHint("Starts the timer over")
        .accessibilityAddTraits(.isButton)
        // VoiceOver's double tap and a keyboard are deliberate enough not to need the hold.
        .accessibilityAction {
            model.reset()
            resets += 1
        }
        .background {
            Button("Reset") {
                guard !model.isPristine else { return }
                model.reset()
                resets += 1
            }
            .keyboardShortcut("r", modifiers: [])
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func press(_ down: Bool) {
        ticker?.cancel()
        ticker = nil
        withAnimation(Motion.press) { holding = down }
        if down {
            withAnimation(.linear(duration: Self.holdTime)) { fill = 1 }
            ticker = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard !Task.isCancelled else { return }
                    ticks += 1
                }
            }
        } else {
            ticks = 0
            withAnimation(Motion.glide) { fill = 0 }
        }
    }
}

/// Takes the timer off the room's screen and puts it back.
///
/// The key is as wide lit as not, with one title and both icons laid out and one of them shown.
/// When it grew to say "Blacked out" its amber arrived outside the margin. The monitor says what
/// state the screen is in.
private struct BlackoutKey: View {
    @Environment(TimerModel.self) private var model

    var body: some View {
        let on = model.blackout
        Button { model.blackout.toggle() } label: {
            VStack(spacing: 3) {
                ZStack {
                    Image(systemName: "eye.slash").opacity(on ? 0 : 1)
                    Image(systemName: "eye.slash.fill").opacity(on ? 1 : 0)
                }
                .font(.body.weight(.semibold))
                Text("Black out")
                    .font(.footnote.weight(.semibold))
            }
        }
        .buttonStyle(on ? KeyStyle.primary() : KeyStyle(fill: Theme.raised))
        .animation(Motion.state, value: on)
        .keyboardShortcut("b", modifiers: [])
        .sensoryFeedback(.selection, trigger: on)
        .accessibilityLabel("Black out")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Moves the number on the screen: a countdown gets more or less time, a stopwatch has its time
/// already counted shifted. Holding a key repeats it.
struct NudgeRow: View {
    @Environment(TimerModel.self) private var model
    /// Told of every nudge so the monitor can show what was just added up.
    var onNudge: (TimeInterval) -> Void
    @State private var taps = 0

    private struct Step: Identifiable {
        var title: String
        var spoken: String
        var seconds: TimeInterval
        var id: TimeInterval { seconds }
    }

    private static let steps = [
        Step(title: "−1 min", spoken: "Take off 1 minute", seconds: -60),
        Step(title: "−10 s", spoken: "Take off 10 seconds", seconds: -10),
        Step(title: "+10 s", spoken: "Add 10 seconds", seconds: 10),
        Step(title: "+1 min", spoken: "Add 1 minute", seconds: 60),
    ]

    var body: some View {
        HStack(spacing: Theme.keyGap) {
            ForEach(Self.steps) { step in
                Button {
                    model.step(by: step.seconds)
                    taps += 1
                    onNudge(step.seconds)
                } label: {
                    Text(step.title)
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }
                .buttonStyle(KeyStyle())
                .buttonRepeatBehavior(.enabled)
                .accessibilityLabel(step.spoken)
            }
        }
        .frame(height: 48)
        .sensoryFeedback(.selection, trigger: taps)
    }
}

extension TimerModel {
    /// One press of a nudge key: more or less time for a countdown, the time already counted
    /// shifted for a stopwatch.
    ///
    /// Nothing animates for it. The keys repeat while held, and before a start they edit the
    /// length itself, which passes over the lengths in the row: an animation that follows the
    /// length (the highlight gliding to a length and away again) would be started and cut off
    /// several times a second.
    func step(by seconds: TimeInterval) {
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            switch mode {
            case .countdown: adjust(by: seconds)
            case .stopwatch: shiftElapsed(by: seconds)
            }
        }
    }
}
