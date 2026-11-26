import SwiftUI

/// Everything touched while a talk is running, top to bottom in the order it is reached for:
/// what the room sees, how long it is set for, the transport, the nudges.
struct LiveColumn: View {
    @Binding var sheet: ControlSheet?
    /// A tall window opens with the mode and the way into Setup. A wide one has Setup beside the
    /// column, with the mode at the top of it, and no height to spare on a phone.
    var showsHeader: Bool
    @State private var echo = NudgeEcho()

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                header.padding(.bottom, 12)
            }
            // The monitor is the one flexible thing in the column: in a window too short for
            // everything it gives up height (and, staying 16:9, width) before any key does.
            Monitor(echo: echo)
                .layoutPriority(-1)
            Caption()
            LengthRow(sheet: $sheet)
                .padding(.bottom, Theme.rowGap)
            Transport()
                .padding(.bottom, Theme.rowGap)
            NudgeRow { echo.add($0) }
        }
    }

    private var header: some View {
        HStack(spacing: 0) {
            // On an iPad on its end the column is 640 wide, and two words do not need it all.
            ModeSwitch()
                .frame(maxWidth: 400)
            Spacer(minLength: Theme.keyGap)
            Button { sheet = .setup } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(KeyStyle())
            .frame(width: 44, height: 44)
            .accessibilityLabel("Setup")
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
            // The old words go at once and the new ones fade in (`KeyTitle`). Fading through
            // each other they were "Externalscreennected" for most of the change.
            KeyTitle(DisplayCopy.short(kinds))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(connected ? Theme.text : Theme.secondary)
                .lineLimit(1)
        }
        .animation(Motion.state, value: kinds)
        // The operator is looking at the stage, not at this corner: a screen arriving or
        // dropping is felt.
        .sensoryFeedback(trigger: connected) { _, connected in
            connected ? .success : .warning
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DisplayCopy.title(kinds))
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
    /// For the pill, which shares its line with what the timer is set to: on a phone the two
    /// have 361 points between them, and "On the external screen" left a countdown that had run
    /// over no room to say since when.
    static func short(_ kinds: Set<DisplayKind>) -> String {
        switch (kinds.contains(.external), kinds.contains(.window)) {
        case (true, true): "Screen and a window"
        case (true, false): "External screen"
        case (false, true): "Display window"
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

// MARK: - Caption

/// The line under the monitor: whether anyone can see the timer, and what it is set to and when
/// it will be done. Words only; the keys start under it.
private struct Caption: View {
    var body: some View {
        HStack(spacing: 12) {
            // The pill keeps its words whole and the other side makes do with what is left.
            DisplayPill()
                .fixedSize()
                .layoutPriority(1)
            // Once a second is all an end time needs.
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Summary(now: context.date)
            }
        }
        .frame(height: 40)
    }
}

private struct Summary: View {
    @Environment(TimerModel.self) private var model
    let now: Date

    private enum Stage { case ready, running, paused, over, finished }

    var body: some View {
        let phase = model.snapshot(at: now).phase
        let summary = summary
        // The line ends at the column's edge, so when its end changes ("ends 2:10 AM" to
        // "paused") all of it moves. Faded from one to the other, the length was on the line
        // twice, a little apart. So the old line goes at once and the new one fades in, as the
        // word on a key does. Within a stage (a nudge, the end time a minute on) it is a cut.
        ZStack {
            summary.text
                .font(.subheadline)
                .foregroundStyle(Theme.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .id(summary.stage)
                .transition(Motion.swap)
        }
        .animation(Motion.state, value: summary.stage)
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

    /// The mode is not named here: the switch that sets it says which it is.
    private var summary: (text: Text, stage: Stage) {
        let elapsed = model.elapsed(at: now)
        switch model.mode {
        case .stopwatch:
            if model.isRunning {
                return (Text("Started \(Self.clock(now.addingTimeInterval(-elapsed)))"), .running)
            }
            return model.isPristine ? (Text("Counts up"), .ready) : (Text("Paused"), .paused)
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
                return (Text("\(length)\(amber)"), .ready)
            }
            if model.isFinished {
                return (Text("\(length)\(extra) · finished"), .finished)
            }
            if !model.isRunning {
                return (Text("\(length)\(extra) · paused"), .paused)
            }
            let end = Self.clock(now.addingTimeInterval(remaining))
            if remaining > 0 {
                return (Text("\(length)\(extra) · ends \(end)"), .running)
            }
            let over = Text("over since \(end)").fontWeight(.semibold).foregroundStyle(Theme.alert)
            return (Text("\(length)\(extra) · \(over)"), .over)
        }
    }

    private static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
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

    var body: some View {
        Group {
            switch model.mode {
            case .countdown:
                HStack(spacing: Theme.keyGap) {
                    // Side by side where they fit (an iPad), a strip to swipe where they do not.
                    ViewThatFits(in: .horizontal) {
                        track(flexible: true)
                            .keyGlass()
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal, showsIndicators: false) {
                                track(flexible: false)
                            }
                            .modifier(FadingWhereCut())
                            .onAppear {
                                // The first lengths are in view as it is; one further along
                                // is brought to the middle.
                                if isPreset && model.duration > 10 * 60 {
                                    proxy.scrollTo(model.duration, anchor: .center)
                                }
                            }
                        }
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
        // A new length starts the timer over, which mid-talk is never what a stray tap meant. It
        // asks with an alert in the middle of the screen: a confirmation dialog is, on iOS 26, a
        // bubble hanging off the row, and it read as a tooltip.
        .alert(
            "Start over?",
            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }),
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

/// For the strip of lengths inside its track: an end where more lengths are out of view fades
/// out, so a label is never cut through by the track's edge, and an end with nothing beyond it
/// is left alone. Knowing how far a strip is scrolled takes iOS 18; before that the labels are
/// cut by the edge as they were.
private struct FadingWhereCut: ViewModifier {
    @State private var hidden = Hidden()

    /// How strongly each end fades, 0 to 1: all the way once 12 points are out of view there.
    private struct Hidden: Equatable {
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
    }

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content
                .onScrollGeometryChange(for: Hidden.self) { geometry in
                    let before = geometry.visibleRect.minX
                    let after = geometry.contentSize.width - geometry.visibleRect.maxX
                    return Hidden(leading: min(max(before / 12, 0), 1), trailing: min(max(after / 12, 0), 1))
                } action: { _, hidden in
                    self.hidden = hidden
                }
                .mask {
                    HStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(1 - hidden.leading), .black], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 28)
                        Color.black
                        LinearGradient(colors: [.black, .black.opacity(1 - hidden.trailing)], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 28)
                    }
                }
        } else {
            content
        }
    }
}

/// Where the chosen length's key is, for the lozenge. Nothing when no key is chosen.
private struct ChosenBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// A key in a track (the lengths, the mode): no body of its own, only a light under the finger.
struct SegmentStyle: ButtonStyle {
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
