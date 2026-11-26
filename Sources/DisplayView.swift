import SwiftUI

/// What the room sees. Also used, scaled down, as the monitor on the control surface.
///
/// Read from the back of a room, so the time is as large as the screen allows and everything
/// else gets out of its way: a message takes the bottom third as a card, the clock a corner.
/// What moves here moves once and settles; nothing loops in front of a speaker.
struct DisplayView: View {
    @Environment(TimerModel.self) private var model

    var body: some View {
        // The face reads the model in its own body: a paused timer ticks once a minute, and a
        // message or a blackout must not wait for the next tick to show.
        TimelineView(.periodic(from: .now, by: model.tickInterval)) { context in
            Face(now: context.date)
        }
        .background(.black)
    }
}

private struct Face: View {
    @Environment(TimerModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let now: Date

    var body: some View {
        let snapshot = model.snapshot(at: now)
        let flash = model.blackout ? 0 : Self.flash(snapshot)
        GeometryReader { geo in
            // One unit is the height of a 16:9 screen, so a taller window letterboxes the layout
            // instead of stretching it.
            let unit = min(geo.size.height, geo.size.width * 9 / 16)
            ZStack {
                Color(red: 0.55 * flash, green: 0.04 * flash, blue: 0.02 * flash)
                content(snapshot, flash: flash, unit: unit, width: geo.size.width)
                    .opacity(model.blackout ? 0 : 1)
            }
            // Blacking out dims like house lights rather than cutting.
            .animation(Motion.paced(.easeInOut(duration: 0.35)), value: model.blackout)
        }
    }

    private func content(_ snapshot: TimerModel.Snapshot, flash: Double, unit: CGFloat, width: CGFloat) -> some View {
        let message = model.showMessage ? model.message.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let sharing = !message.isEmpty
        let color = Self.color(snapshot.phase, flash: flash)
        let full = digitSize(snapshot.text, unit: unit, width: width, sharing: false)
        let shared = digitSize(snapshot.text, unit: unit, width: width, sharing: true)
        return VStack(spacing: 0) {
            // The digits are set once at full size and scaled to make room for a message, not
            // set again smaller: scaling animates, a font size does not.
            Color.clear
                .overlay {
                    // The colour and the digits are two layers, the digits cut out of the colour,
                    // because they change differently. White to amber to red is a change of
                    // state and fades. A new time is a cut: 1:00 becoming 10:00 is narrower type
                    // in another place, and a number that travels there (it did, at an angle,
                    // whenever the colour changed in the same moment) is a number nobody can read.
                    color
                        .animation(Motion.paced(.easeInOut(duration: 0.6)), value: snapshot.phase)
                        .mask {
                            Text(snapshot.text)
                                .font(.system(size: full, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.3)
                                .contentTransition(.identity)
                                .transaction { $0.animation = nil }
                        }
                        // Tall enough for the line at full size, so only a time too wide for the
                        // estimate in `ems` is ever shrunk by the text itself.
                        .frame(width: max(width - unit * 0.10, 1), height: unit * 0.8)
                        // The block still glides up as one when a message takes the bottom of the
                        // screen; without this the digits inside it would jump there instead.
                        .geometryGroup()
                        .scaleEffect(sharing ? shared / full : 1)
                        .accessibilityElement()
                        .accessibilityLabel(snapshot.text)
                        .accessibilityAddTraits(.updatesFrequently)
                }

            if sharing {
                Text(message)
                    .font(.system(size: unit * 0.15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.35)
                    .padding(.horizontal, unit * 0.05)
                    .frame(maxWidth: .infinity)
                    .frame(height: unit * 0.29)
                    .background(Theme.text, in: RoundedRectangle(cornerRadius: unit * 0.055, style: .continuous))
                    .padding(.horizontal, unit * 0.04)
                    .padding(.bottom, unit * 0.04)
                    .transition(reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .bottom).combined(with: .opacity))
            }

            if let progress = snapshot.progress {
                ProgressBar(progress: progress, color: color, height: max(unit * 0.018, 3))
                    // The bar turns with the digits, not ahead of them.
                    .animation(Motion.paced(.easeInOut(duration: 0.6)), value: snapshot.phase)
            }
        }
        .animation(Motion.paced(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.55, bounce: 0.12)), value: sharing)
        .overlay(alignment: .topTrailing) {
            if model.showClock {
                Text(now, format: .dateTime.hour().minute())
                    .font(.system(size: unit * 0.07, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondary.blended(with: .white, by: flash))
                    .padding(.top, unit * 0.04)
                    .padding(.trailing, unit * 0.06)
                    .transition(AnyTransition.opacity)
            }
        }
        .animation(Motion.fade, value: model.showClock)
    }

    /// As large as fits. Sized for the widest time this run will show rather than the one
    /// showing now, so the digits do not jump when 10:00 becomes 9:59.
    private func digitSize(_ text: String, unit: CGFloat, width: CGFloat, sharing: Bool) -> CGFloat {
        let widest = model.mode == .countdown ? TimerModel.format(Int(model.target)) : text
        let ems = max(Self.ems(text), Self.ems(widest))
        let byWidth = (width - unit * 0.10) / ems
        let byHeight = unit * (sharing ? 0.50 : 0.62)
        return max(min(byWidth, byHeight), 1)
    }

    /// Advance width in ems of SF Rounded bold with tabular digits, rounded up; anything it
    /// underestimates is caught by the text's own scale factor.
    private static func ems(_ text: String) -> CGFloat {
        text.reduce(0) { $0 + ($1 == ":" ? 0.34 : 0.68) }
    }

    /// 0...1: how red the background is. It pulses once a second for the first six seconds past
    /// zero so the speaker notices.
    private static func flash(_ snapshot: TimerModel.Snapshot) -> Double {
        guard let over = snapshot.overtime, over < 6 else { return 0 }
        return (1 - cos(over * 2 * .pi)) / 2
    }

    private static func color(_ phase: TimerModel.Phase, flash: Double) -> Color {
        switch phase {
        case .normal: Theme.text
        case .warning: Theme.warning
        // On the flash the digits go white: red on red is the one moment nobody can read.
        case .overtime: Theme.overtime.blended(with: .white, by: flash)
        }
    }
}

private extension Color {
    /// A straight mix in sRGB; `Color.mix` needs iOS 18.
    func blended(with other: Color, by amount: Double) -> Color {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        UIColor(self).getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        UIColor(other).getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let t = CGFloat(min(max(amount, 0), 1))
        return Color(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            opacity: a1 + (a2 - a1) * t
        )
    }
}

private struct ProgressBar: View {
    var progress: Double
    var color: Color
    var height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.14))
                Rectangle().fill(color).frame(width: geo.size.width * (1 - progress))
            }
        }
        .frame(height: height)
    }
}
