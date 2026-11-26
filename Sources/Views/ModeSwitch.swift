import SwiftUI

/// Countdown or stopwatch. It is the first thing decided about a talk, so it is the first thing
/// on the surface and not a row in Setup, where the owner did not find it.
///
/// One track with a lozenge under the mode that is on, as the lengths have. The lozenge is a
/// lighter grey and not amber: amber is for the key to press and for what is live in front of
/// the room, and a mode is neither. Switching starts the timer over, so once a run has begun it
/// asks first.
struct ModeSwitch: View {
    @Environment(TimerModel.self) private var model
    /// Glass where the switch sits on the ground above the monitor; this fill where it sits
    /// among the cards beside the controls.
    var fill: Color?
    @State private var pending: TimerModel.Mode?

    /// How far the lozenge sits inside a segment, which is as tall as the track.
    private static let inset = CGSize(width: 2, height: 4)

    /// `asking` puts the question up at once, as if that mode had been tapped mid-run. Only a
    /// screenshot asks for it.
    init(fill: Color? = nil, asking: TimerModel.Mode? = nil) {
        self.fill = fill
        _pending = State(initialValue: asking)
    }

    var body: some View {
        Group {
            if let fill {
                track.background(fill, in: Capsule())
            } else {
                track.keyGlass()
            }
        }
        .animation(Motion.glide, value: model.mode)
        .sensoryFeedback(.selection, trigger: model.mode)
        // An alert in the middle of the screen, not a confirmation dialog: on iOS 26 that is a
        // bubble hanging off the segment that was tapped, and it read as a tooltip.
        .alert(
            "Switch mode?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            presenting: pending
        ) { mode in
            Button("Switch and reset", role: .destructive) { model.mode = mode }
            Button("Keep going", role: .cancel) {}
        } message: { mode in
            Text("The timer has already started. Switching to \(mode.title) resets it.")
        }
    }

    /// The words are drawn twice, as the lengths are: dim in the track, and bright ones over them
    /// cut to the lozenge's shape. A word is then bright exactly where the lozenge is under it.
    /// Drawn once and lit by the mode, the words changed at the tap and the lozenge took a third
    /// of a second to follow: the bright word stood on the bare track, the dim one on the lozenge.
    private var track: some View {
        let modes = TimerModel.Mode.allCases
        return HStack(spacing: 0) {
            ForEach(modes) { mode in
                Button { pick(mode) } label: {
                    label(mode).foregroundStyle(Theme.secondary)
                }
                .buttonStyle(SegmentStyle(inset: Self.inset))
                .accessibilityAddTraits(model.mode == mode ? .isSelected : [])
            }
        }
        .padding(.horizontal, Self.inset.width)
        .frame(height: 44)
        .background {
            GeometryReader { proxy in
                lozenge(in: proxy.size, of: modes).foregroundStyle(Theme.chosen)
            }
        }
        .overlay {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(modes) { mode in
                        label(mode).foregroundStyle(Theme.text)
                    }
                }
                .padding(.horizontal, Self.inset.width)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .mask { lozenge(in: proxy.size, of: modes) }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func label(_ mode: TimerModel.Mode) -> some View {
        Text(mode.title)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One lozenge that moves, under the mode that is on.
    private func lozenge(in size: CGSize, of modes: [TimerModel.Mode]) -> some View {
        let segment = (size.width - 2 * Self.inset.width) / CGFloat(modes.count)
        let index = CGFloat(modes.firstIndex(of: model.mode) ?? 0)
        return Capsule()
            .frame(width: segment - 2 * Self.inset.width, height: size.height - 2 * Self.inset.height)
            .position(x: Self.inset.width + segment * (index + 0.5), y: size.height / 2)
    }

    private func pick(_ mode: TimerModel.Mode) {
        guard mode != model.mode else { return }
        if model.isPristine { model.mode = mode } else { pending = mode }
    }
}
