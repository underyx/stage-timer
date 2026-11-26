import SwiftUI

/// What is decided before a talk rather than during one: the mode, how the countdown behaves,
/// what else the screen shows, and the connection. A sheet when the window is tall, a column
/// beside the controls when it is wide.
struct SetupPanel: View {
    @Environment(TimerModel.self) private var model
    /// What the cards are filled with; it depends on what the panel sits on.
    var cardFill: Color
    /// The key colour one step up from `cardFill`.
    var keyFill: Color
    var open: (ControlSheet) -> Void
    @State private var pendingMode: TimerModel.Mode?

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 18) {
            Picker("Mode", selection: mode) {
                ForEach(TimerModel.Mode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            // Changing mode starts the timer over, so mid-run it asks first.
            .confirmationDialog(
                "Switch mode?",
                isPresented: Binding(get: { pendingMode != nil }, set: { if !$0 { pendingMode = nil } }),
                titleVisibility: .visible,
                presenting: pendingMode
            ) { mode in
                Button("Reset and switch to \(mode.title)", role: .destructive) { model.mode = mode }
                Button("Keep going", role: .cancel) {}
            } message: { _ in
                Text("The timer has already started. Switching mode resets it.")
            }

            // A stopwatch has nothing to decide beforehand. Shifting its time is done mid-talk and
            // has its key in the live column, where the lengths are for a countdown.
            if model.mode == .countdown {
                SetupCard("Countdown", fill: cardFill) {
                    Button { open(.length) } label: {
                        SetupRow("Custom length") {
                            Text(TimerModel.format(Int(model.duration))).monospacedDigit()
                            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    RowDivider()
                    SetupRow("Turn amber at") {
                        Picker("Turn amber at", selection: $model.warnAt) {
                            Text("Off").tag(TimeInterval(0))
                            Text("30 s left").tag(TimeInterval(30))
                            Text("1 min left").tag(TimeInterval(60))
                            Text("2 min left").tag(TimeInterval(120))
                            Text("5 min left").tag(TimeInterval(300))
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                    RowDivider()
                    Toggle("Keep counting past zero", isOn: $model.countOvertime).setupRow()
                }
            }

            // "Keep running when locked" exists only in builds that ship its background mode.
            SetupCard(
                "Screen",
                footer: LockKeepalive.isAvailable
                    ? "Keeps the connected screen counting after the top button is pressed. Off, the screen freezes on the last time until the device is unlocked."
                    : nil,
                fill: cardFill
            ) {
                Toggle("Show the time of day", isOn: $model.showClock).setupRow()
                if LockKeepalive.isAvailable {
                    RowDivider()
                    Toggle("Keep running when locked", isOn: $model.keepRunningWhenLocked).setupRow()
                }
            }

            ConnectionCard(fill: cardFill, keyFill: keyFill)
        }
        .tint(Theme.amber)
    }

    private var mode: Binding<TimerModel.Mode> {
        Binding {
            model.mode
        } set: { new in
            guard new != model.mode else { return }
            if model.isPristine { model.mode = new } else { pendingMode = new }
        }
    }
}

// MARK: - Cards

private struct SetupCard<Content: View>: View {
    private let title: String
    private let footer: String?
    private let fill: Color
    private let content: Content

    init(_ title: String, footer: String? = nil, fill: Color, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.fill = fill
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).sectionLabel().padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .background(fill, in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// A label on the left and whatever it is set to on the right.
private struct SetupRow<Trailing: View>: View {
    private let title: String
    private let trailing: Trailing

    init(_ title: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title).foregroundStyle(Theme.text)
            Spacer(minLength: 12)
            // The value keeps its line; in a narrow column it is the label that wraps.
            HStack(spacing: 6) { trailing }
                .foregroundStyle(Theme.secondary)
                .fixedSize()
        }
        .setupRow()
    }
}

private struct RowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.hairline)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

private extension View {
    func setupRow() -> some View {
        font(.body)
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .frame(minHeight: 52)
    }
}

// MARK: - Connection

/// What is connected, what to do about it, and the display window for an extended screen.
private struct ConnectionCard: View {
    @Environment(TimerModel.self) private var model
    var fill: Color
    var keyFill: Color

    var body: some View {
        let kinds = Set(model.displays.values)
        let multipleScenes = UIApplication.shared.supportsMultipleScenes
        VStack(alignment: .leading, spacing: 6) {
            Text("Connection").sectionLabel().padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    ConnectionDot(connected: !kinds.isEmpty)
                        .padding(.top, 6)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(DisplayCopy.title(kinds))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Theme.text)
                        Text(DisplayCopy.hint(kinds, multipleScenes: multipleScenes))
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if kinds.contains(.window) {
                    Button("Close the display window") { DisplaySceneDelegate.closeWindows() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(KeyStyle.flat(keyFill))
                        .frame(height: 44)
                } else if multipleScenes {
                    Button("Open a display window") { DisplaySceneDelegate.open() }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(KeyStyle.flat(keyFill))
                        .frame(height: 44)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
            .animation(Motion.state, value: kinds)
        }
    }
}

// MARK: - Wheels

/// Hours, minutes and seconds on wheels: a length to set, or a change to add or remove.
struct DurationPicker: View {
    var title = "Length"
    /// The wheels hold a change to add or remove rather than a total to set. A running clock
    /// moves on while the wheels are being turned, so only a change can be applied to it exactly.
    var relative = false
    /// What the button that applies a total says; it warns when applying will reset a run.
    var confirm = "Set"
    let initial: TimeInterval
    /// Receives the total, or the signed change when `relative`.
    let onDone: (TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var h = 0
    @State private var m = 0
    @State private var s = 0
    @State private var removing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                if relative {
                    Picker("Direction", selection: $removing) {
                        Text("Add").tag(false)
                        Text("Remove").tag(true)
                    }
                    .pickerStyle(.segmented)
                }
                // The wheels stand in a well of the ground colour, as the message does in its card.
                HStack(spacing: 0) {
                    wheel($h, 0..<24, "h")
                    wheel($m, 0..<60, "min")
                    wheel($s, 0..<60, "s")
                }
                .padding(.horizontal, 8)
                .background(Theme.ground, in: RoundedRectangle(cornerRadius: Theme.groupRadius, style: .continuous))
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(relative ? (removing ? "Remove" : "Add") : confirm) {
                        let total = TimeInterval(h * 3600 + m * 60 + s)
                        onDone(removing ? -total : total)
                        dismiss()
                    }
                    .disabled(h + m + s == 0)
                }
            }
        }
        .presentationDetents([.medium])
        // The surface colour, not the glass the system would give a sheet that stops halfway:
        // through that the Start key behind lit the title up in amber, and the sheet is read
        // in the same dim room as the rest.
        .presentationBackground(Theme.surface)
        .tint(Theme.amber)
        .preferredColorScheme(.dark)
        .onAppear {
            let total = Int(initial)
            (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        }
    }

    private func wheel(_ value: Binding<Int>, _ range: Range<Int>, _ unit: String) -> some View {
        Picker(unit, selection: value) {
            ForEach(range, id: \.self) { Text("\($0) \(unit)").monospacedDigit().tag($0) }
        }
        .pickerStyle(.wheel)
    }
}
