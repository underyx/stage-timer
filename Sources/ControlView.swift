import SwiftUI

struct ControlView: View {
    @Environment(TimerModel.self) private var model
    @State private var editingDuration = false

    var body: some View {
        GeometryReader { geo in
            let wide = geo.size.width > geo.size.height && geo.size.width > 700
            let layout = wide
                ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
                : AnyLayout(VStackLayout(spacing: 0))
            layout {
                VStack(spacing: 20) {
                    preview
                    transport
                    DisplayStatus()
                }
                .padding(24)
                .frame(maxWidth: wide ? geo.size.width * 0.58 : .infinity)
                settings
            }
        }
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $editingDuration) {
            DurationPicker(initial: model.duration) { model.setDuration($0) }
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

            if model.mode == .countdown {
                HStack(spacing: 8) {
                    adjustButton("−1 min", -60)
                    adjustButton("−10 s", -10)
                    adjustButton("+10 s", 10)
                    adjustButton("+1 min", 60)
                }
            }
        }
        .controlSize(.large)
    }

    private func adjustButton(_ title: String, _ seconds: TimeInterval) -> some View {
        Button { model.adjust(by: seconds) } label: {
            Text(title).monospacedDigit().frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
    }

    private var settings: some View {
        @Bindable var model = model
        return Form {
            Section {
                Picker("Mode", selection: $model.mode) {
                    ForEach(TimerModel.Mode.allCases) { Text($0.rawValue).tag($0) }
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

            Section("Message") {
                TextField("Shown under the timer", text: $model.message)
                    .submitLabel(.done)
                    .onSubmit { model.showMessage = !model.message.isEmpty }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(["Wrap up", "5 minutes left", "Questions", "Speak up", "Break"], id: \.self) { text in
                            Button(text) {
                                model.message = text
                                model.showMessage = true
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
                Toggle("Show on display", isOn: $model.showMessage)
                    .disabled(model.message.isEmpty)
            }

            Section("Display") {
                Toggle("Show clock", isOn: $model.showClock)
                Toggle("Black out", isOn: $model.blackout)
                    .keyboardShortcut("b", modifiers: [])
            }
        }
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, 40, for: .scrollContent)
    }
}

private struct DisplayStatus: View {
    @Environment(TimerModel.self) private var model

    var body: some View {
        let kinds = Set(model.displays.values)
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: kinds.isEmpty ? "display.trianglebadge.exclamationmark" : "display")
                .foregroundStyle(kinds.isEmpty ? Color.secondary : Color.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(kinds)).font(.subheadline.weight(.medium))
                Text(hint(kinds)).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if kinds.contains(.window) {
                Button("Close window") { DisplaySceneDelegate.closeWindows() }
                    .buttonStyle(.bordered)
            } else {
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
        return "Mirroring screens pick the timer up automatically. With an extended display, open a display window and move it there."
    }
}

private struct DurationPicker: View {
    let initial: TimeInterval
    let onDone: (TimeInterval) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var h = 0
    @State private var m = 0
    @State private var s = 0

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                wheel($h, 0..<24, "h")
                wheel($m, 0..<60, "min")
                wheel($s, 0..<60, "s")
            }
            .padding()
            .navigationTitle("Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Set") {
                        onDone(TimeInterval(h * 3600 + m * 60 + s))
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
