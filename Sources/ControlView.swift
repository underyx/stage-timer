import SwiftUI

/// The sheets the control surface can raise. One at a time: asking for another swaps it.
enum ControlSheet: String, Identifiable {
    case setup, length, elapsed
    var id: String { rawValue }
}

/// The operator's side of the app.
///
/// It is split by when a control is used, not by what it controls. What is touched during a talk
/// (the transport, the nudges, the message, blackout) is always on screen and large; what is
/// decided before one lives in Setup, all but the mode, which is on the surface itself. Nothing
/// that would throw a running timer away happens on a single tap: Reset is held, and a new
/// length or mode asks first. The surface is always dark.
struct ControlView: View {
    @Environment(TimerModel.self) private var model
    @State private var sheet: ControlSheet?

    var body: some View {
        GeometryReader { geo in
            if geo.size.width > geo.size.height && geo.size.width >= 700 {
                wide(geo.size)
            } else {
                tall
            }
        }
        .background(Theme.ground.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .tint(Theme.amber)
        .preferredColorScheme(.dark)
        // Keys are sized for fingers, not for text; let type grow, but not until rows break.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .sheet(item: $sheet) { sheet in
            content(of: sheet)
                .environment(model)
        }
    }

    /// A phone, or an iPad on its end: one column, Setup behind a button.
    private var tall: some View {
        ScrollView {
            VStack(spacing: 24) {
                LiveColumn(sheet: $sheet, showsHeader: true)
                MessageCard()
            }
            .frame(maxWidth: 640)
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
    }

    /// Landscape: the live column on the left, the message and Setup on the right.
    private func wide(_ size: CGSize) -> some View {
        HStack(alignment: .top, spacing: 24) {
            LiveColumn(sheet: $sheet, showsHeader: false)
                .frame(width: (size.width - 72) * 0.6)

            ScrollView {
                VStack(spacing: 18) {
                    MessageCard()
                    SetupPanel(showsMode: true, cardFill: Theme.surface, keyFill: Theme.raised) { sheet = $0 }
                }
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func content(of sheet: ControlSheet) -> some View {
        switch sheet {
        case .setup:
            NavigationStack {
                ScrollView {
                    SetupPanel(cardFill: Theme.raised, keyFill: Theme.lifted) { self.sheet = $0 }
                        .padding(16)
                }
                .background(Theme.surface)
                .navigationTitle("Setup")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { self.sheet = nil }
                    }
                }
            }
            .presentationBackground(Theme.surface)
            .tint(Theme.amber)
            .preferredColorScheme(.dark)
        case .length:
            DurationPicker(
                title: "Length",
                confirm: model.isPristine ? "Set" : "Set and reset",
                initial: model.duration
            ) { model.setDuration($0) }
        case .elapsed:
            DurationPicker(title: "Adjust stopwatch", relative: true, initial: 0) {
                model.shiftElapsed(by: $0)
            }
        }
    }
}
