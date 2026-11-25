import SwiftUI

/// Start, pause and reset: the row a thumb rests on.
///
/// Reset is the one control here that cannot be taken back, and it sits beside the one pressed
/// most, so it has to be held. A held key hides its own face under the finger, so the feedback
/// for the hold is drawn on the Start key next to it, which the finger never covers.
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
    private static let radius: CGFloat = 18

    var body: some View {
        HStack(spacing: 8) {
            Button { model.toggle() } label: {
                Label {
                    Text(title).contentTransition(.opacity)
                } icon: {
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill")
                        .contentTransition(.symbolEffect(.replace))
                }
                .font(.title2.weight(.bold))
            }
            .buttonStyle(model.isRunning ? KeyStyle(fill: Theme.raised, radius: Self.radius) : KeyStyle.primary(radius: Self.radius))
            .animation(Motion.state, value: model.isRunning)
            .overlay { holdFeedback }
            .keyboardShortcut(.space, modifiers: [])

            resetKey
                .frame(width: 104)
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
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        return GeometryReader { geo in
            ZStack(alignment: .trailing) {
                Theme.surface
                Theme.hold.frame(width: geo.size.width * fill)
            }
            .overlay {
                Text("Keep holding to reset")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
            }
        }
        .clipShape(shape)
        .opacity(holding ? 1 : 0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var resetKey: some View {
        let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
        return VStack(spacing: 2) {
            Label("Reset", systemImage: "arrow.counterclockwise")
                .font(.body.weight(.semibold))
            Text("hold")
                .font(.caption2.weight(.medium))
                .foregroundStyle(holding ? Color.white : Theme.secondary)
        }
        .foregroundStyle(holding ? Color.white : Theme.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(holding ? Theme.hold : Theme.raised, in: shape)
        .scaleEffect(holding && !reduceMotion ? 0.95 : 1)
        .opacity(model.isPristine ? 0.4 : 1)
        .contentShape(shape)
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
        HStack(spacing: 8) {
            ForEach(Self.steps) { step in
                Button {
                    switch model.mode {
                    case .countdown: model.adjust(by: step.seconds)
                    case .stopwatch: model.shiftElapsed(by: step.seconds)
                    }
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
