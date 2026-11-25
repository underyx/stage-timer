import SwiftUI

/// The control surface's palette and its two kinds of button.
///
/// The colours come from the app icon: a warm charcoal room, the cream of the TV's body, the
/// amber of its screen. The surface is always dark, whatever the system appearance: an operator's
/// iPad must not be a lamp in a dimmed room.
enum Theme {
    /// The window behind everything.
    static let ground = Color(red: 0.059, green: 0.055, blue: 0.051)
    /// Cards, and keys that sit straight on the ground.
    static let surface = Color(red: 0.110, green: 0.106, blue: 0.098)
    /// Keys that matter more, and anything sitting on a card.
    static let raised = Color(red: 0.169, green: 0.161, blue: 0.149)
    /// One step up again, for a key on a raised card.
    static let lifted = Color(red: 0.227, green: 0.216, blue: 0.200)
    static let hairline = Color.white.opacity(0.08)

    static let text = Color(red: 0.953, green: 0.933, blue: 0.902)
    /// 9:1 on `ground`, 7:1 on `raised`.
    static let secondary = Color(red: 0.702, green: 0.678, blue: 0.643)

    /// The accent: the one thing to press, and whatever is live on the screen right now.
    static let amber = Color(red: 1, green: 0.639, blue: 0.102)
    static let onAmber = Color(red: 0.122, green: 0.078, blue: 0)
    static let connected = Color(red: 0.298, green: 0.816, blue: 0.541)
    /// Small red text on the ground; the display's own red is too dark at this size.
    static let alert = Color(red: 1, green: 0.478, blue: 0.431)
    /// What fills the Reset key while it is held.
    static let hold = Color(red: 0.761, green: 0.212, blue: 0.169)

    // The display. Yellower than the accent so the last minute and overtime differ in lightness as
    // well as hue from the back of a room.
    static let warning = Color(red: 1, green: 0.76, blue: 0.1)
    static let overtime = Color(red: 1, green: 0.23, blue: 0.19)
    /// The ink on the display's message card.
    static let ink = Color(red: 0.078, green: 0.067, blue: 0.051)
}

/// The few curves everything moves on. Quick and slightly sprung: the surface should feel like
/// hardware answering, never like a screen performing.
enum Motion {
    /// A key going down and coming back.
    static let press = Animation.spring(duration: 0.22, bounce: 0.3)
    /// A selection travelling from one place to another.
    static let glide = Animation.spring(duration: 0.35, bounce: 0.2)
    /// Something changing what it is: Start becoming Pause, a card going live.
    static let state = Animation.spring(duration: 0.42, bounce: 0.16)
    static let fade = Animation.easeInOut(duration: 0.3)
}

/// A key: fills whatever frame it is given, so rows of keys are sized by their row.
struct KeyStyle: ButtonStyle {
    var fill = Theme.surface
    var ink = Theme.text
    var radius: CGFloat = 14

    static func primary(radius: CGFloat = 14) -> KeyStyle {
        KeyStyle(fill: Theme.amber, ink: Theme.onAmber, radius: radius)
    }

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, style: self)
    }

    // `isEnabled` only reaches a view, not the style itself.
    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let style: KeyStyle
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: style.radius, style: .continuous)
            configuration.label
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(style.ink)
                .background(style.fill, in: shape)
                .overlay { shape.fill(.white.opacity(configuration.isPressed ? 0.14 : 0)) }
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .animation(Motion.state, value: style.fill)
                .contentShape(shape)
        }
    }
}

/// A chip: as wide as its label (or, `flexible`, sharing its row equally), amber when selected.
struct ChipStyle: ButtonStyle {
    var selected = false
    var fill = Theme.surface
    var radius: CGFloat = 12
    var flexible = false
    var padding: CGFloat = 14
    /// Chips in one row share a namespace so the amber glides from the old choice to the new one.
    var selection: Namespace.ID?

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(.subheadline.weight(selected ? .bold : .medium))
            .lineLimit(1)
            .foregroundStyle(selected ? Theme.onAmber : Theme.text)
            .padding(.horizontal, padding)
            .frame(minWidth: 50, maxWidth: flexible ? .infinity : nil, minHeight: 44)
            .background {
                ZStack {
                    shape.fill(fill)
                    if selected {
                        if let selection {
                            shape.fill(Theme.amber).matchedGeometryEffect(id: "selected", in: selection)
                        } else {
                            shape.fill(Theme.amber).transition(AnyTransition.opacity)
                        }
                    }
                }
            }
            .overlay { shape.fill(.white.opacity(configuration.isPressed ? 0.14 : 0)) }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.press, value: configuration.isPressed)
            .contentShape(shape)
    }
}

extension View {
    /// The small capitals over a card.
    func sectionLabel() -> some View {
        font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .kerning(0.6)
            .foregroundStyle(Theme.secondary)
    }
}
