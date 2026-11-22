import SwiftUI

/// Interactive waveform with playback progress (tap or drag to seek).
struct WaveformView: View {
    let peaks: [Float]
    let progress: Double
    var onSeek: ((Double) -> Void)?

    var body: some View {
        GeometryReader { proxy in
            let count = max(peaks.count, 1)
            let spacing: CGFloat = 2
            let barWidth = max(1.5, (proxy.size.width - spacing * CGFloat(count - 1)) / CGFloat(count))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(displayPeaks.enumerated()), id: \.offset) { index, peak in
                    let played = Double(index) / Double(count) <= progress
                    Capsule()
                        .fill(played ? AnyShapeStyle(Theme.roseGradient) : AnyShapeStyle(Theme.silverLight))
                        .frame(width: barWidth, height: max(3, CGFloat(peak) * proxy.size.height))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onSeek?(min(max(0, value.location.x / proxy.size.width), 1))
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel("Forme d'onde")
        .accessibilityValue("\(Int(progress * 100)) %")
    }

    private var displayPeaks: [Float] {
        peaks.isEmpty ? Array(repeating: 0.08, count: 60) : peaks
    }
}

/// Monogram avatar of a voice.
struct VoiceAvatar: View {
    let voice: Voice
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            Circle()
                .fill(voice.gender == .female ? AnyShapeStyle(Theme.roseGradient) : AnyShapeStyle(Theme.blackGradient))
            Circle()
                .strokeBorder(Theme.silverGradient, lineWidth: 1.5)
            Text(voice.initial)
                .font(.system(size: size * 0.42, weight: .semibold, design: .serif))
                .foregroundStyle(voice.gender == .female ? Theme.black : Color.white)
        }
        .frame(width: size, height: size)
        .overlay(alignment: .bottomTrailing) {
            Text(voice.language.flag)
                .font(.system(size: size * 0.3))
                .offset(x: 3, y: 3)
        }
        .accessibilityHidden(true)
    }
}

/// Slider with title, value and reset.
struct ValueSlider: View {
    let title: String
    let systemImage: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let defaultValue: Double
    let format: (Double) -> String
    var minLabel: String?
    var maxLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(format(value))
                    .font(.subheadline.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.roseDeep)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: value)
                if abs(value - defaultValue) > step / 2 {
                    Button {
                        withAnimation(.snappy) { value = defaultValue }
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.silver)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Réinitialiser \(title)")
                }
            }
            Slider(value: $value, in: range, step: step)
                .tint(Theme.rose)
            if let minLabel, let maxLabel {
                HStack {
                    Text(minLabel)
                    Spacer()
                    Text(maxLabel)
                }
                .font(.caption2)
                .foregroundStyle(Theme.silver)
            }
        }
    }
}

/// Small status chip.
struct StatusChip: View {
    let text: String
    let systemImage: String
    var tint: Color = Theme.roseDeep

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.roseMist))
            .overlay(Capsule().strokeBorder(Theme.silverLight, lineWidth: 0.8))
    }
}

/// Brand wordmark: "Diana" in pink, "VoiceStudio" in silver.
struct Wordmark: View {
    var size: CGFloat = 30

    var body: some View {
        HStack(spacing: 0) {
            Text("Diana")
                .foregroundStyle(Theme.roseGradient)
            Text("Voice")
                .foregroundStyle(Theme.ink)
            Text("Studio")
                .foregroundStyle(Theme.silverGradient)
        }
        .font(.system(size: size, weight: .bold, design: .serif))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("DianaVoiceStudio")
    }
}

extension Int64 {
    var formattedBytes: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
