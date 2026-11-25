import SwiftUI

/// A note for the speaker. Typing, tapping a preset and pressing Done only edit the text; the
/// button at the bottom alone decides whether the room sees it, and the whole card lights up
/// while it does.
struct MessageCard: View {
    @Environment(TimerModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var editing: Bool

    private static let presets = ["Wrap up", "5 minutes left", "Questions", "Speak up", "Break"]
    private static let inset: CGFloat = 14

    var body: some View {
        @Bindable var model = model
        let live = model.showMessage
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Message").sectionLabel()
                Spacer()
                if live {
                    OnScreenTally(pulsing: !reduceMotion)
                        .transition(AnyTransition.opacity.combined(with: .move(edge: .trailing)))
                }
            }
            .frame(height: 16)

            TextField("A note for the speaker", text: $model.message)
                .focused($editing)
                .submitLabel(.done)
                .font(.body)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(editing ? Theme.amber.opacity(0.7) : Theme.hairline)
                }
                .animation(Motion.fade, value: editing)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Self.presets, id: \.self) { text in
                        Button(text) { model.message = text }
                            .buttonStyle(ChipStyle(fill: Theme.raised, radius: 22))
                    }
                }
            }
            // Out to the card's own edges, so the last one in view is cut by the card.
            .contentMargins(.horizontal, Self.inset, for: .scrollContent)
            .padding(.horizontal, -Self.inset)

            Button { model.showMessage.toggle() } label: {
                Label {
                    Text(live ? "Hide from screen" : "Show on screen").contentTransition(.opacity)
                } icon: {
                    Image(systemName: live ? "eye.slash" : "display")
                        .contentTransition(.symbolEffect(.replace))
                }
                .font(.callout.weight(.semibold))
            }
            .buttonStyle(live ? KeyStyle.primary() : KeyStyle(fill: Theme.raised))
            .frame(height: 48)
            .disabled(model.message.isEmpty)
        }
        .padding(Self.inset)
        .background(Theme.surface, in: shape)
        // Going live draws the amber round the card rather than switching it on.
        .overlay {
            shape.inset(by: 0.75)
                .trim(from: 0, to: live ? 1 : 0)
                .stroke(Theme.amber, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .opacity(live ? 1 : 0)
        }
        .animation(reduceMotion ? Motion.fade : .easeInOut(duration: 0.5), value: live)
        .sensoryFeedback(trigger: live) { _, live in
            .impact(weight: live ? .medium : .light)
        }
    }
}

/// The tally light: amber, with a slow halo, for as long as the message is in front of the room.
private struct OnScreenTally: View {
    var pulsing: Bool

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                if pulsing {
                    Circle().fill(Theme.amber)
                        .phaseAnimator([false, true]) { halo, out in
                            halo.scaleEffect(out ? 2.6 : 1).opacity(out ? 0 : 0.5)
                        } animation: { out in
                            out ? .easeOut(duration: 1.6) : .linear(duration: 0.01)
                        }
                }
                Circle().fill(Theme.amber)
            }
            .frame(width: 7, height: 7)
            Text("On screen")
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .kerning(0.6)
                .foregroundStyle(Theme.amber)
        }
        .accessibilityElement(children: .combine)
    }
}
