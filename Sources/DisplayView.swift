import SwiftUI

/// What the audience sees. Also used, scaled down, as the live preview on the iPad.
struct DisplayView: View {
    @Environment(TimerModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let snapshot = model.snapshot(at: context.date)
            GeometryReader { geo in
                let h = min(geo.size.height, geo.size.width * 9 / 16)
                ZStack {
                    background(snapshot, now: context.date)
                    if !model.blackout {
                        VStack(spacing: h * 0.02) {
                            Text(snapshot.text)
                                .font(.system(size: h * 0.42, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(color(snapshot.phase))
                                .lineLimit(1)
                                .minimumScaleFactor(0.1)
                                .contentTransition(.identity)
                            if model.showMessage && !model.message.isEmpty {
                                Text(model.message)
                                    .font(.system(size: h * 0.1, weight: .medium))
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.3)
                            }
                        }
                        .padding(.horizontal, h * 0.06)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        if model.showClock {
                            Text(context.date, format: .dateTime.hour().minute())
                                .font(.system(size: h * 0.06, weight: .medium, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(.white.opacity(0.55))
                                .padding(h * 0.04)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        }

                        if let progress = snapshot.progress {
                            ProgressBar(progress: progress, color: color(snapshot.phase), height: max(h * 0.012, 2))
                                .frame(maxHeight: .infinity, alignment: .bottom)
                        }
                    }
                }
            }
        }
        .background(.black)
    }

    private func color(_ phase: TimerModel.Phase) -> Color {
        switch phase {
        case .normal: .white
        case .warning: Color(red: 1, green: 0.76, blue: 0.1)
        case .overtime: Color(red: 1, green: 0.23, blue: 0.19)
        }
    }

    /// Pulse the background red for the first few seconds after zero so the speaker notices.
    @ViewBuilder
    private func background(_ snapshot: TimerModel.Snapshot, now: Date) -> some View {
        if let over = snapshot.overtime, over < 6, !model.blackout {
            let pulse = (cos(over * 2 * .pi) + 1) / 2
            Color(red: 0.55 * (1 - pulse), green: 0, blue: 0)
        } else {
            Color.black
        }
    }
}

private struct ProgressBar: View {
    var progress: Double
    var color: Color
    var height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle().fill(.white.opacity(0.12))
                Rectangle().fill(color).frame(width: geo.size.width * (1 - progress))
            }
        }
        .frame(height: height)
    }
}
