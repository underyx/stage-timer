import SwiftUI

struct ControlView: View {
    @Environment(TimerModel.self) private var model
    @State private var editingDuration = false
    @State private var shiftingElapsed = false

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height && geo.size.width > 700
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))
            let compact = geo.size.width < 600 || geo.size.height < 600
            let main = VStack(spacing: compact ? 14 : 20) {
                preview
                transport
                DisplayStatus(compact: compact)
            }
            .padding(compact ? 16 : 24)
            .padding(.top, compact ? -16 : 0)
            layout {
                if wide {
                    // A landscape iPhone is too short for the preview and controls; let that column scroll.
                    ViewThatFits(in: .vertical) {
                        main
                        ScrollView { main }
                    }
                    .frame(maxWidth: geo.size.width * 0.58)
                } else {
                    main.fixedSize(horizontal: false, vertical: true)
                }
                settings(compact: compact)
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $editingDuration) {
            DurationPicker(initial: model.duration) { model.setDuration($0) }
        }
        .sheet(isPresented: $shiftingElapsed) {
            DurationPicker(title: "Adjust stopwatch", relative: true, initial: 0) { model.shiftElapsed(by: $0) }
        }
    }

    private var preview: some View {
        DisplayView()
            .aspectRatio(16 / 9, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.08))
            }
            .overlay(alignment: .topLeading) {
                if model.blackout {
                    Label("Blacked out", systemImage: "eye.slash")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(12)
                }
            }
            .accessibilityLabel("Display preview")
    }

    private var transport: some View {
        @Bindable var model = model
        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                Button {
                    model.toggle()
                } label: {
                    Label(model.isRunning ? "Pause" : (model.isPristine ? "Start" : "Resume"),
                          systemImage: model.isRunning ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isRunning ? .orange : .green)
                .keyboardShortcut(.space, modifiers: [])

                Button {
                    model.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(model.isPristine)
                .keyboardShortcut("r", modifiers: [])
            }
            .font(.title3.weight(.semibold))

            HStack(spacing: 8) {
                adjustButton("−1 min", -60)
                adjustButton("−10 s", -10)
                adjustButton("+10 s", 10)
                adjustButton("+1 min", 60)
            }
        }
        .controlSize(.large)
    }

    /// Moves the number on the display by `seconds` in either mode: a countdown's target shifts,
    /// a stopwatch's time already counted does.
    private func adjustButton(_ title: String, _ seconds: TimeInterval) -> some View {
        Button {
            switch model.mode {
            case .countdown: model.adjust(by: seconds)
            case .stopwatch: model.shiftElapsed(by: seconds)
            }
        } label: {
            Text(title).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        // A stopwatch at 0:00 has nothing to take away.
        .disabled(model.mode == .stopwatch && seconds < 0 && model.isPristine)
    }

    private func settings(compact: Bool) -> some View {
        @Bindable var model = model
        return Form {
            Section {
                Picker("Mode", selection: $model.mode) {
                    ForEach(TimerModel.Mode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }

            if model.mode == .countdown {
                Section("Duration") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 8) {
                        ForEach([1, 2, 3, 5, 10, 15, 20, 30, 45, 60], id: \.self) { minutes in
                            let selected = model.duration == TimeInterval(minutes * 60)
                            Button { model.setDuration(TimeInterval(minutes * 60)) } label: {
                                Text("\(minutes)′").frame(maxWidth: .infinity)
                            }
                                .buttonStyle(.bordered)
                                .tint(selected ? .accentColor : .secondary)
                                .fontWeight(selected ? .semibold : .regular)
                        }
                    }
                    .padding(.vertical, 4)
                    Button {
                        editingDuration = true
                    } label: {
                        LabeledContent("Custom…", value: TimerModel.format(Int(model.duration)))
                    }
                    Picker("Turn amber at", selection: $model.warnAt) {
                        Text("Off").tag(TimeInterval(0))
                        Text("30 s").tag(TimeInterval(30))
                        Text("1 min").tag(TimeInterval(60))
                        Text("2 min").tag(TimeInterval(120))
                        Text("5 min").tag(TimeInterval(300))
                    }
                    Toggle("Count up past zero", isOn: $model.countOvertime)
                }
            }

            if model.mode == .stopwatch {
                Section {
                    Button("Add time already spent…") { shiftingElapsed = true }
                } footer: {
                    Text("Started late? Add what has already passed. The stopwatch keeps running while you do.")
                }
            }

            Section("Message") {
                // Typing, tapping a preset and pressing Done only edit the text; the toggle alone
                // decides whether the audience sees it.
                TextField("Shown under the timer", text: $model.message)
                    .submitLabel(.done)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(["Wrap up", "5 minutes left", "Questions", "Speak up", "Break"], id: \.self) { text in
                            Button(text) { model.message = text }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                Toggle("Show on display", isOn: $model.showMessage)
                    .disabled(model.message.isEmpty)
            }

            Section {
                Toggle("Show clock", isOn: $model.showClock)
                Toggle("Black out", isOn: $model.blackout)
                    .keyboardShortcut("b", modifiers: [])
                if LockKeepalive.isAvailable {
                    Toggle("Keep running when locked", isOn: $model.keepRunningWhenLocked)
                }
            } header: {
                Text("Display")
            } footer: {
                if LockKeepalive.isAvailable {
                    Text("Keeps the connected display counting after the top button is pressed. Off, the display freezes on the last time until the device is unlocked.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 40, for: .scrollContent)
        .contentMargins(.top, compact ? 4 : nil, for: .scrollContent)
    }
}

private struct DisplayStatus: View {
    @Environment(TimerModel.self) private var model
    /// Phones can't spare the second line; the hint only matters until the first display is connected.
    var compact = false

    var body: some View {
        let kinds = Set(model.displays.values)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: kinds.isEmpty ? "display.trianglebadge.exclamationmark" : "display")
                .foregroundStyle(kinds.isEmpty ? Color.secondary : Color.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(kinds)).font(.subheadline.weight(.medium))
                if !compact {
                    Text(hint(kinds)).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if kinds.contains(.window) {
                Button("Close window") { DisplaySceneDelegate.closeWindows() }
                    .buttonStyle(.bordered)
            } else if UIApplication.shared.supportsMultipleScenes {
                Button("Open display window") { DisplaySceneDelegate.open() }
                    .buttonStyle(.bordered)
            }
        }
        .font(.subheadline)
    }

    private func title(_ kinds: Set<DisplayKind>) -> String {
        switch (kinds.contains(.external), kinds.contains(.window)) {
        case (true, true): "External screen and display window active"
        case (true, false): "Showing on external screen"
        case (false, true): "Display window open"
        case (false, false): "No display connected"
        }
    }

    private func hint(_ kinds: Set<DisplayKind>) -> String {
        if kinds.contains(.window) {
            return "Drag it to the external screen and make it full screen."
        }
        if kinds.contains(.external) {
            return "The iPad keeps these controls; the screen shows only the timer."
        }
        guard UIApplication.shared.supportsMultipleScenes else {
            return "Connect a display by cable or AirPlay Screen Mirroring and it shows only the timer."
        }
        return "Mirroring screens pick the timer up automatically. With an extended display, open a display window and move it there."
    }
}

private struct DurationPicker: View {
    var title = "Duration"
    /// The wheels hold a change to add or remove rather than a total to set. A running clock
    /// moves on while the wheels are being turned, so only a change can be applied to it exactly.
    var relative = false
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
                HStack(spacing: 0) {
                    wheel($h, 0..<24, "h")
                    wheel($m, 0..<60, "min")
                    wheel($s, 0..<60, "s")
                }
            }
            .padding()
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(relative ? (removing ? "Remove" : "Add") : "Set") {
                        let total = TimeInterval(h * 3600 + m * 60 + s)
                        onDone(removing ? -total : total)
                        dismiss()
                    }
                    .disabled(h + m + s == 0)
                }
            }
        }
        .presentationDetents([.medium])
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
