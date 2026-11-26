import SwiftUI

/// Everything touched while a talk is running, top to bottom in the order it is reached for:
/// what the room sees, how long it is set for, the transport, the nudges.
struct LiveColumn: View {
    @Binding var sheet: ControlSheet?
    /// Tall windows keep Setup in a sheet and need the button; wide ones show it alongside.
    var showsSetupButton: Bool
    /// A landscape phone has no height to spare for it.
    var showsHeader = true
    @State private var echo = NudgeEcho()

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header.padding(.bottom, 8)
            }
            // The monitor is the one flexible thing in the column: in a window too short for
            // everything it gives up height (and, staying 16:9, width) before any key does.
            Monitor(echo: echo)
                .layoutPriority(-1)
            StatusStrip()
            LengthRow(sheet: $sheet)
                .padding(.bottom, 12)
            Transport()
                .padding(.bottom, 8)
            NudgeRow { echo.add($0) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            DisplayPill()
            Spacer(minLength: 0)
            if showsSetupButton {
                Button { sheet = .setup } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(KeyStyle())
                .frame(width: 44, height: 44)
                .accessibilityLabel("Setup")
            }
        }
        .frame(height: 44)
    }
}

// MARK: - Monitor

/// The screen as the room sees it, with what only the operator needs laid over it.
private struct Monitor: View {
    @Environment(TimerModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var echo: NudgeEcho
    @State private var starts = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        DisplayView()
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(shape)
            .overlay { shape.strokeBorder(.white.opacity(0.1)) }
            // Starting lights the bezel for a moment, the way a tube warms up.
            .overlay {
                shape.strokeBorder(Theme.amber, lineWidth: 2)
                    .phaseAnimator([0.0, 1.0], trigger: starts) { border, glow in
                        border.opacity(glow)
                    } animation: { glow in
                        Motion.paced(glow == 1 ? .easeOut(duration: 0.1) : .easeOut(duration: 0.8))
                    }
            }
            .overlay(alignment: .topLeading) { badge.padding(12) }
            .overlay(alignment: .bottomLeading) { nudgeEcho.padding(12).padding(.bottom, 4) }
            .onChange(of: model.isRunning) { _, running in
                if running && !reduceMotion { starts += 1 }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Screen preview")
    }

    private enum Status { case none, blackedOut, finished, paused }

    private var status: Status {
        if model.blackout { return .blackedOut }
        if model.isFinished { return .finished }
        return model.isRunning || model.isPristine ? .none : .paused
    }

    private var badge: some View {
        ZStack(alignment: .topLeading) {
            switch status {
            case .none: EmptyView()
            case .blackedOut: MonitorBadge(title: "Blacked out", systemImage: "eye.slash.fill")
            case .finished: MonitorBadge(title: "Finished", systemImage: "checkmark")
            case .paused: MonitorBadge(title: "Paused", systemImage: "pause.fill", breathing: !reduceMotion)
            }
        }
        .animation(Motion.state, value: status)
    }

    /// The sum of the nudges just made, so three taps of +10 s read as +0:30 without arithmetic.
    private var nudgeEcho: some View {
        ZStack {
            if echo.visible {
                Text(echo.text)
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.onAmber)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.amber, in: Capsule())
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.glide, value: echo.visible)
        .animation(Motion.glide, value: echo.total)
        .accessibilityHidden(true)
    }
}

private struct MonitorBadge: View {
    var title: String
    var systemImage: String
    /// A paused timer should not be mistaken for a running one at a glance.
    var breathing = false

    var body: some View {
        Group {
            if breathing {
                label.phaseAnimator([1.0, 0.5]) { label, level in
                    label.opacity(level)
                } animation: { _ in
                    .easeInOut(duration: 1.1)
                }
            } else {
                label
            }
        }
        .transition(AnyTransition.scale(scale: 0.85, anchor: .topLeading).combined(with: .opacity))
    }

    private var label: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.black.opacity(0.7), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.16)) }
    }
}

/// What the nudge keys have added up to in the last moment.
@MainActor @Observable
final class NudgeEcho {
    private(set) var total: TimeInterval = 0
    private(set) var visible = false
    @ObservationIgnored private var hide: Task<Void, Never>?

    var text: String {
        (total < 0 ? "−" : "+") + TimerModel.format(Int(abs(total)))
    }

    func add(_ seconds: TimeInterval) {
        total = (visible ? total : 0) + seconds
        visible = total != 0
        hide?.cancel()
        hide = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.visible = false
        }
    }
}

// MARK: - Connection

/// Whether anyone can see the timer, in one line.
struct DisplayPill: View {
    @Environment(TimerModel.self) private var model

    var body: some View {
        let kinds = Set(model.displays.values)
        let connected = !kinds.isEmpty
        HStack(spacing: 8) {
            ConnectionDot(connected: connected)
            Text(DisplayCopy.short(kinds))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(connected ? Theme.text : Theme.secondary)
                .contentTransition(.opacity)
                .lineLimit(1)
        }
        .animation(Motion.state, value: kinds)
        // The operator is looking at the stage, not at this corner: a screen arriving or
        // dropping is felt.
        .sensoryFeedback(trigger: connected) { _, connected in
            connected ? .success : .warning
        }
        .accessibilityElement(children: .combine)
    }
}

struct ConnectionDot: View {
    var connected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if connected {
                Circle().fill(Theme.connected)
            } else {
                Circle().strokeBorder(Theme.secondary, lineWidth: 2)
            }
            if !reduceMotion {
                // One ring leaves the dot when a screen connects.
                Circle()
                    .stroke(connected ? Theme.connected : .clear, lineWidth: 1.5)
                    .phaseAnimator([0, 1, 2], trigger: connected) { ring, step in
                        ring.scaleEffect(step == 2 ? 3 : 1).opacity(step == 1 ? 0.8 : 0)
                    } animation: { step in
                        step == 2 ? Motion.paced(.easeOut(duration: 0.9)) : .linear(duration: 0.01)
                    }
            }
        }
        .frame(width: 9, height: 9)
        .accessibilityHidden(true)
    }
}

/// The words for what is connected, in one place for the pill and the Setup card.
enum DisplayCopy {
    static func short(_ kinds: Set<DisplayKind>) -> String {
        switch (kinds.contains(.external), kinds.contains(.window)) {
        case (true, true): "On the external screen and a window"
        case (true, false): "On the external screen"
        case (false, true): "Display window open"
        case (false, false): "No display connected"
        }
    }

    static func title(_ kinds: Set<DisplayKind>) -> String {
        switch (kinds.contains(.external), kinds.contains(.window)) {
        case (true, true): "External screen and display window active"
        case (true, false): "Showing on the external screen"
        case (false, true): "Display window open"
        case (false, false): "No display connected"
        }
    }

    static func hint(_ kinds: Set<DisplayKind>, multipleScenes: Bool) -> String {
        if kinds.contains(.window) {
            return "Drag it to the external screen and make it full screen."
        }
        if kinds.contains(.external) {
            return "This device keeps the controls; the screen shows only the timer."
        }
        guard multipleScenes else {
            return "Connect a display by cable or AirPlay Screen Mirroring and it shows only the timer."
        }
        return "Mirroring screens pick the timer up automatically. With an extended display, open a display window and move it there."
    }
}

// MARK: - Status strip

/// One line on what the timer is set to and when it will be done, and the blackout key.
private struct StatusStrip: View {
    var body: some View {
        HStack(spacing: 12) {
            // Once a second is all an end time needs.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Summary(now: context.date)
            }
            BlackoutButton()
        }
        .frame(height: 52)
    }
}

private struct Summary: View {
    @Environment(TimerModel.self) private var model
    let now: Date

    private enum Stage { case ready, running, paused, over, finished }

    var body: some View {
        let phase = model.snapshot(at: now).phase
        let summary = summary
        summary.text
            .font(.subheadline)
            .foregroundStyle(Theme.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .contentTransition(.opacity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(Motion.fade, value: summary.stage)
            // The operator's eyes are on the stage when these happen: the last stretch is a
            // tap on the wrist, running out is a proper buzz.
            .sensoryFeedback(trigger: phase) { _, phase in
                guard model.isRunning || model.isFinished else { return nil }
                switch phase {
                case .normal: return nil
                case .warning: return .impact(weight: .light)
                case .overtime: return .warning
                }
            }
    }

    private var summary: (text: Text, stage: Stage) {
        let elapsed = model.elapsed(at: now)
        switch model.mode {
        case .stopwatch:
            if model.isRunning {
                return (Text("Stopwatch · started \(Self.clock(now.addingTimeInterval(-elapsed)))"), .running)
            }
            return model.isPristine ? (Text("Stopwatch"), .ready) : (Text("Stopwatch · paused"), .paused)
        case .countdown:
            let length = Text(TimerModel.format(Int(model.duration)))
                .fontWeight(.semibold)
                .foregroundStyle(Theme.text)
            let extra = model.extraTime == 0
                ? ""
                : " \(model.extraTime < 0 ? "−" : "+")\(TimerModel.format(Int(abs(model.extraTime))))"
            let remaining = model.target - elapsed
            if model.isPristine {
                let amber = model.warnAt > 0 ? " · amber at \(TimerModel.format(Int(model.warnAt)))" : ""
                return (Text("Countdown \(length)\(amber)"), .ready)
            }
            if model.isFinished {
                return (Text("Countdown \(length)\(extra) · finished"), .finished)
            }
            if !model.isRunning {
                return (Text("Countdown \(length)\(extra) · paused"), .paused)
            }
            let end = Self.clock(now.addingTimeInterval(remaining))
            if remaining > 0 {
                return (Text("Countdown \(length)\(extra) · ends \(end)"), .running)
            }
            let over = Text("over since \(end)").fontWeight(.semibold).foregroundStyle(Theme.alert)
            return (Text("Countdown \(length)\(extra) · \(over)"), .over)
        }
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

private struct BlackoutButton: View {
    @Environment(TimerModel.self) private var model

    var body: some View {
        Button { model.blackout.toggle() } label: {
            // One title, and both icons laid out with one of them shown, so the key is exactly
            // as wide lit as not. When it grew to say "Blacked out" its amber arrived outside
            // the margin, and the line beside it lost the room for "over since 12:16 AM". The
            // monitor above says what state the screen is in.
            Label {
                Text("Black out")
            } icon: {
                ZStack {
                    Image(systemName: "eye.slash").opacity(model.blackout ? 0 : 1)
                    Image(systemName: "eye.slash.fill").opacity(model.blackout ? 1 : 0)
                }
            }
            .fontWeight(.semibold)
        }
        .buttonStyle(ChipStyle(selected: model.blackout))
        .animation(Motion.fade, value: model.blackout)
        .keyboardShortcut("b", modifiers: [])
        .sensoryFeedback(.selection, trigger: model.blackout)
        .accessibilityAddTraits(model.blackout ? .isSelected : [])
    }
}

// MARK: - Length

/// How long the countdown is set for. In stopwatch mode the row holds the one thing a stopwatch
/// can be set to instead, so the keys below it never move.
private struct LengthRow: View {
    @Environment(TimerModel.self) private var model
    @Binding var sheet: ControlSheet?
    @State private var pending: TimeInterval?
    /// Counts the lengths chosen here, for the click that answers a pick.
    @State private var picks = 0

    private static let presets = [1, 2, 3, 5, 10, 15, 20, 30, 45, 60]
    /// The strip of lengths, as a coordinate space its content is measured in.
    private static let strip = "lengths"

    var body: some View {
        Group {
            switch model.mode {
            case .countdown:
                HStack(spacing: 8) {
                    // Side by side where they fit (an iPad), a strip to swipe where they do not.
                    ViewThatFits(in: .horizontal) {
                        track(flexible: true)
                            .keyGlass()
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                track(flexible: false)
                                    .background {
                                        GeometryReader { content in
                                            Color.clear.preference(key: StripFrame.self, value: content.frame(in: .named(Self.strip)))
                                        }
                                    }
                            }
                            .coordinateSpace(.named(Self.strip))
                            .onAppear {
                                // The first lengths are in view as it is; one further along
                                // is brought to the middle.
                                if isPreset && model.duration > 10 * 60 {
                                    proxy.scrollTo(model.duration, anchor: .center)
                                }
                            }
                        }
                        .fadingWhereCut()
                        .clipShape(Capsule())
                        .keyGlass()
                    }
                    // Any other length. Never lit: the line above the row says what the
                    // length is, and a light here would hop on and off as the nudge keys
                    // pass the lengths in the track.
                    Button { sheet = .length } label: {
                        Image(systemName: "pencil")
                            .font(.body.weight(.semibold))
                    }
                    .buttonStyle(KeyStyle())
                    .frame(width: 44)
                    .accessibilityLabel("Custom length")
                    .accessibilityValue(isPreset ? "" : TimerModel.format(Int(model.duration)))
                }
                .sensoryFeedback(.selection, trigger: picks)
            case .stopwatch:
                Button { sheet = .elapsed } label: {
                    Label("Add time already spent…", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(KeyStyle())
            }
        }
        .frame(height: 44)
        // A new length starts the timer over, which mid-talk is never what a stray tap meant.
        .confirmationDialog(
            "Start over?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible,
            presenting: pending
        ) { seconds in
            Button("Reset to \(TimerModel.format(Int(seconds)))", role: .destructive) {
                choose(seconds)
            }
            Button("Keep going", role: .cancel) {}
        } message: { _ in
            Text("The timer has already started. A new length resets it.")
        }
    }

    private var isPreset: Bool {
        Self.presets.contains { TimeInterval($0 * 60) == model.duration }
    }

    private func track(flexible: Bool) -> some View {
        LengthTrack(presets: Self.presets, chosen: model.duration, flexible: flexible) { pick($0) }
            // The amber glides from one length to another. A length that is not in the track
            // lights nothing, and one reached with the nudge keys lights without a glide
            // (`TimerModel.step`): the highlight must not travel while a key is held.
            .animation(Motion.glide, value: model.duration)
    }

    private func pick(_ seconds: TimeInterval) {
        if !model.isPristine {
            pending = seconds
        } else if seconds != model.duration {
            choose(seconds)
        }
    }

    private func choose(_ seconds: TimeInterval) {
        picks += 1
        model.setDuration(seconds)
    }
}

/// The lengths as one track, with a lozenge of amber on the chosen one.
///
/// The lozenge is one view that moves, not a fill in every key that swaps: two fills that
/// cross-faded on the way left the amber almost invisible for the first part of the glide. The
/// labels are drawn twice, light for the track and dark for the amber, the dark ones cut to the
/// lozenge's shape, so a label is legible wherever the lozenge is over it.
private struct LengthTrack: View {
    var presets: [Int]
    var chosen: TimeInterval
    /// Sharing the width equally, or each as wide as it needs for a strip that scrolls.
    var flexible: Bool
    var pick: (TimeInterval) -> Void

    /// How far the lozenge sits inside a key, which is as tall as the track.
    private static let inset = CGSize(width: 2, height: 4)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(presets, id: \.self) { minutes in
                let seconds = TimeInterval(minutes * 60)
                Button { pick(seconds) } label: {
                    label(minutes).foregroundStyle(Theme.text)
                }
                .buttonStyle(SegmentStyle(inset: Self.inset))
                .anchorPreference(key: ChosenBounds.self, value: .bounds) { chosen == seconds ? $0 : nil }
                .id(seconds)
                .accessibilityLabel(minutes == 1 ? "1 minute" : "\(minutes) minutes")
                .accessibilityAddTraits(chosen == seconds ? .isSelected : [])
            }
        }
        .padding(.horizontal, Self.inset.width)
        .overlayPreferenceValue(ChosenBounds.self) { anchor in
            GeometryReader { proxy in
                if let anchor {
                    let rect = proxy[anchor].insetBy(dx: Self.inset.width, dy: Self.inset.height)
                    ZStack {
                        lozenge(rect).foregroundStyle(Theme.amber)
                        HStack(spacing: 0) {
                            ForEach(presets, id: \.self) { minutes in
                                label(minutes).foregroundStyle(Theme.onAmber)
                            }
                        }
                        .padding(.horizontal, Self.inset.width)
                        .mask { lozenge(rect) }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .transition(AnyTransition.opacity)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func label(_ minutes: Int) -> some View {
        Text("\(minutes)m")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .frame(minWidth: 54, maxWidth: flexible ? .infinity : nil)
            .frame(height: 44)
    }

    private func lozenge(_ rect: CGRect) -> some View {
        Capsule()
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

/// Where the content of a strip that scrolls sideways is, measured from the strip's own leading
/// edge: how much of it is out of view on either side.
private struct StripFrame: PreferenceKey {
    static var defaultValue: CGRect { .zero }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private extension View {
    /// For the strip of lengths inside its track: an end where more lengths are out of view fades
    /// out, so a label is never cut through by the track's edge, and an end with nothing beyond
    /// it is left alone. It is rubbed out of the strip rather than masked, because a mask
    /// cannot be told how far the strip has been scrolled and an overlay can.
    func fadingWhereCut() -> some View {
        overlayPreferenceValue(StripFrame.self) { content in
            GeometryReader { strip in
                let width: CGFloat = 28
                let leading = min(max(-content.minX / 12, 0), 1)
                let trailing = min(max((content.maxX - strip.size.width) / 12, 0), 1)
                HStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(leading), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: width)
                    Spacer(minLength: 0)
                    LinearGradient(colors: [.clear, .black.opacity(trailing)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: width)
                }
            }
            .blendMode(.destinationOut)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .compositingGroup()
    }
}

/// Where the chosen length's key is, for the lozenge. Nothing when no key is chosen.
private struct ChosenBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A key in the track: no body of its own, only a light under the finger.
private struct SegmentStyle: ButtonStyle {
    var inset: CGSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Capsule()
                    .fill(.white.opacity(configuration.isPressed ? 0.14 : 0))
                    .padding(.horizontal, inset.width)
                    .padding(.vertical, inset.height)
            }
            .contentShape(Rectangle())
            .animation(Motion.press, value: configuration.isPressed)
    }
}
