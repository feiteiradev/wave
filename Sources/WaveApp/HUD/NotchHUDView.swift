import SwiftUI
import WaveCore

/// The temporary HUD that wraps the notch (PRD §26).
///
/// Deliberately identical for Raw and Clean — it never reveals which mode was
/// activated (PRD §26.2).
struct NotchHUDView: View {
    let state: HUDState
    let waveform: [Float]

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(
            Capsule(style: .continuous)
                .fill(.black.opacity(0.85))
                .overlay(Capsule(style: .continuous).strokeBorder(.white.opacity(0.08)))
        )
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
        .animation(.easeOut(duration: 0.18), value: label)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .hidden:
            EmptyView()
        case .recording:
            WaveformView(levels: waveform)
                .frame(width: 96)
        case .processing:
            ProcessingDotsView()
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        case let .error(error):
            Label(error.hudMessage, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .labelStyle(.titleAndIcon)
        case let .toast(message):
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
        }
    }

    private var label: String {
        switch state {
        case .hidden: "hidden"
        case .recording: "recording"
        case .processing: "processing"
        case .done: "done"
        case let .error(error): error.rawValue
        case let .toast(message): message
        }
    }
}

/// An organic waveform driven by the actual captured amplitude (PRD §27).
///
/// Bars are smoothed RMS values, not individual samples — the HUD is a sign of
/// life, not an oscilloscope.
struct WaveformView: View {
    let levels: [Float]

    private let barCount = 24

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width / CGFloat(barCount * 2 - 1)
            HStack(alignment: .center, spacing: width) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.9))
                        .frame(width: width, height: height(at: index, in: geometry.size.height))
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
        }
    }

    private func height(at index: Int, in maxHeight: CGFloat) -> CGFloat {
        guard !levels.isEmpty else { return 2 }
        // Newest sample on the right, so the waveform scrolls the way the
        // speech arrives.
        let position = Double(index) / Double(max(1, barCount - 1))
        let sampleIndex = Int(position * Double(levels.count - 1))
        let level = CGFloat(levels[max(0, min(levels.count - 1, sampleIndex))])
        return max(2, min(maxHeight, level * maxHeight))
    }
}

/// Replaces the waveform once capture stops, so the two phases are never
/// confused (PRD §28).
struct ProcessingDotsView: View {
    @State private var phase = 0.0

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<5, id: \.self) { index in
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .opacity(opacity(for: index))
            }
        }
        .frame(width: 96)
        .onAppear {
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                phase = 5
            }
        }
    }

    private func opacity(for index: Int) -> Double {
        let distance = abs(phase - Double(index))
        return 0.25 + 0.75 * max(0, 1 - distance)
    }
}
