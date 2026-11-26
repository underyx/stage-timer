import SwiftUI

/// The control surface's palette.
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

    /// Whether keys are Liquid Glass where the system has it. Always true in the app. The
    /// tests turn it off to draw the surface as iOS 17 and 18 have it, which no simulator in CI
    /// runs. Unsafe by the compiler's lights only: nothing but a test writes it.
    nonisolated(unsafe) static var glass = true

    /// The corners of a card, and of the monitor. Keys are capsules and have none to choose.
    static let cardRadius: CGFloat = 26
    /// A card inside a sheet or beside the controls, with rows in it.
    static let groupRadius: CGFloat = 22

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
    /// How many times slower than life everything here moves. Always 1 in the app. The tests
    /// that film a change raise it: a simulator in CI draws a frame in about an eighth of a
    /// second, and a glide of a third of a second would be over in two of them. Unsafe by the
    /// compiler's lights only: nothing but a test writes it, from the main thread.
    nonisolated(unsafe) static var slowdown: Double = 1

    /// A key going down and coming back.
    static var press: Animation { paced(.spring(duration: 0.22, bounce: 0.3)) }
    /// A selection travelling from one place to another.
    static var glide: Animation { paced(.spring(duration: 0.35, bounce: 0.2)) }
    /// Something changing what it is: Start becoming Pause, a card going live.
    static var state: Animation { paced(.spring(duration: 0.42, bounce: 0.16)) }
    static var fade: Animation { paced(.easeInOut(duration: 0.3)) }

    /// Any other curve, at the pace the rest is moving at.
    static func paced(_ animation: Animation) -> Animation {
        slowdown == 1 ? animation : animation.speed(1 / slowdown)
    }
}

// MARK: - Keys

/// A key: a capsule that fills whatever frame it is given, so rows of keys are sized by their row.
///
/// A key that sits straight on the ground is Liquid Glass where the system has it (iOS 26 and
/// later) and a flat fill before that. A key on a card is always a flat fill: the cards are the
/// content, and glass is for what floats over it.
struct KeyStyle: ButtonStyle {
    /// The flat fill: on a card, and everywhere before iOS 26.
    var fill = Theme.surface
    var ink = Theme.text
    /// What the glass is tinted with. Nothing, for every key but the one to press.
    var tint: Color?
    var glass = true

    static func primary(glass: Bool = true) -> KeyStyle {
        KeyStyle(fill: Theme.amber, ink: Theme.onAmber, tint: Theme.amber, glass: glass)
    }

    /// A key on a card.
    static func flat(_ fill: Color) -> KeyStyle {
        KeyStyle(fill: fill, glass: false)
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
            let label = configuration.label
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(style.ink)
                .animation(Motion.state, value: style.ink)
            if #available(iOS 26.0, *) {
                if style.glass && Theme.glass {
                    // The glass answers a finger itself, so nothing is drawn here for a press.
                    label
                        .opacity(isEnabled ? 1 : 0.4)
                        .glassEffect(.regular.tint(style.tint).interactive(), in: Capsule())
                        .animation(Motion.state, value: style.tint)
                        .contentShape(Capsule())
                } else {
                    flat(label)
                }
            } else {
                flat(label)
            }
        }

        private func flat(_ label: some View) -> some View {
            label
                .background(style.fill, in: Capsule())
                .overlay { Capsule().fill(.white.opacity(configuration.isPressed ? 0.14 : 0)) }
                .opacity(isEnabled ? 1 : 0.4)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(Motion.press, value: configuration.isPressed)
                .animation(Motion.state, value: style.fill)
                .contentShape(Capsule())
        }
    }
}

/// A chip: a capsule as wide as its label, amber when selected. Glass or flat as a key is.
struct ChipStyle: ButtonStyle {
    var selected = false
    var fill = Theme.surface
    var glass = true

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(selected ? Theme.onAmber : Theme.text)
            .padding(.horizontal, 16)
            .frame(minWidth: 50, minHeight: 44)
        if #available(iOS 26.0, *) {
            if glass && Theme.glass {
                label
                    .glassEffect(.regular.tint(selected ? Theme.amber : nil).interactive(), in: Capsule())
                    .contentShape(Capsule())
            } else {
                flat(label, pressed: configuration.isPressed)
            }
        } else {
            flat(label, pressed: configuration.isPressed)
        }
    }

    private func flat(_ label: some View, pressed: Bool) -> some View {
        label
            .background(selected ? Theme.amber : fill, in: Capsule())
            .overlay { Capsule().fill(.white.opacity(pressed ? 0.14 : 0)) }
            .scaleEffect(pressed ? 0.96 : 1)
            .animation(Motion.press, value: pressed)
            .contentShape(Capsule())
    }
}

extension View {
    /// The body of something that is not a `Button` but sits on the ground like a key: Liquid
    /// Glass where the system has it, the flat fill before that. `lit` floods it with a colour
    /// (Reset while it is held); the colour is drawn in the glass, not as a tint of it, so that
    /// it fades in and out like any other fill.
    @ViewBuilder
    func keyGlass(lit: Color? = nil, fallback: Color = Theme.surface) -> some View {
        if #available(iOS 26.0, *) {
            if Theme.glass {
                background(lit ?? .clear, in: Capsule())
                    .glassEffect(.regular, in: Capsule())
            } else {
                background(lit ?? fallback, in: Capsule())
            }
        } else {
            background(lit ?? fallback, in: Capsule())
        }
    }

    /// A sheet that stops halfway is glass where the system has it. Before that it is the
    /// surface colour, like the cards.
    @ViewBuilder
    func sheetGround() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            presentationBackground(Theme.surface)
        }
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

    /// For a strip that scrolls sideways inside a margin: it runs `margin` further out on both
    /// sides and fades there, so a key that is partly out of view dissolves towards the edge
    /// instead of being cut by a line nobody can see. At rest nothing is faded.
    func bleedingStrip(_ margin: CGFloat) -> some View {
        contentMargins(.horizontal, margin, for: .scrollContent)
            .mask {
                HStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing)
                        .frame(width: margin)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: margin)
                }
            }
            .padding(.horizontal, -margin)
    }
}
