import Foundation

/// Destination of stitched samples (an audio file on device, an array in tests).
protocol AudioSampleSink: AnyObject {
    func write(_ samples: ArraySlice<Float>) throws
}

final class MemorySampleSink: AudioSampleSink {
    private(set) var samples: [Float] = []
    func write(_ samples: ArraySlice<Float>) throws { self.samples.append(contentsOf: samples) }
}

/// Glues synthesized segments together, streaming the result to a sink so that
/// memory stays constant whatever the length of the script.
///
/// * Leading/trailing silence of each segment is trimmed so that the pauses
///   chosen by the user are exact.
/// * When there is a pause, the previous segment fades out and the next one
///   fades in (no clicks).
/// * When there is no pause (a long sentence split in the middle), the two
///   segments overlap with an equal-power cross-fade.
final class AudioStitcher {
    let sampleRate: Double
    let fadeSamples: Int
    let trimSilence: Bool
    private let sink: AudioSampleSink

    /// Last `fadeSamples` of the previous segment, kept back for the cross-fade.
    private var pendingTail: [Float] = []
    private var hasContent = false

    private(set) var framesWritten: Int = 0
    private(set) var peak: Float = 0

    init(sink: AudioSampleSink, sampleRate: Double, crossfadeDuration: Double = 0.02, trimSilence: Bool = true) {
        self.sink = sink
        self.sampleRate = sampleRate
        self.fadeSamples = max(1, Int(crossfadeDuration * sampleRate))
        self.trimSilence = trimSilence
    }

    /// Appends a segment. `pause` is the silence (seconds) inserted before it.
    func append(_ segment: [Float], pauseBefore pause: Double) throws {
        var samples = trimSilence ? Self.trimmed(segment, sampleRate: sampleRate) : segment
        guard !samples.isEmpty else { return }

        if !hasContent {
            Self.applyFade(&samples, range: 0..<min(fadeSamples, samples.count), fadeIn: true)
            hasContent = true
        } else if pause > 0 || pendingTail.isEmpty {
            Self.applyFade(&pendingTail, range: 0..<pendingTail.count, fadeIn: false)
            try emit(pendingTail[...])
            pendingTail = []
            try emitSilence(seconds: pause)
            Self.applyFade(&samples, range: 0..<min(fadeSamples, samples.count), fadeIn: true)
        } else {
            // Equal-power cross-fade between the tail of the previous segment and the head of this one.
            let overlap = min(pendingTail.count, samples.count)
            let offset = pendingTail.count - overlap
            if offset > 0 { try emit(pendingTail[0..<offset]) }
            var mixed = [Float](repeating: 0, count: overlap)
            for i in 0..<overlap {
                let t = (Double(i) + 0.5) / Double(overlap)
                let gainOut = Float(cos(t * .pi / 2))
                let gainIn = Float(sin(t * .pi / 2))
                mixed[i] = pendingTail[offset + i] * gainOut + samples[i] * gainIn
            }
            try emit(mixed[...])
            samples.removeFirst(overlap)
            pendingTail = []
        }

        let keep = min(fadeSamples, samples.count)
        try emit(samples[0..<(samples.count - keep)])
        pendingTail = Array(samples[(samples.count - keep)...])
    }

    /// Flushes the last samples (with a fade-out).
    func finish() throws {
        Self.applyFade(&pendingTail, range: 0..<pendingTail.count, fadeIn: false)
        try emit(pendingTail[...])
        pendingTail = []
    }

    var duration: Double { Double(framesWritten) / sampleRate }

    // MARK: - Helpers

    private func emit(_ slice: ArraySlice<Float>) throws {
        guard !slice.isEmpty else { return }
        for value in slice {
            let magnitude = abs(value)
            if magnitude > peak { peak = magnitude }
        }
        try sink.write(slice)
        framesWritten += slice.count
    }

    private func emitSilence(seconds: Double) throws {
        var remaining = Int(seconds * sampleRate)
        let block = [Float](repeating: 0, count: 4_096)
        while remaining > 0 {
            let n = min(remaining, block.count)
            try sink.write(block[0..<n])
            framesWritten += n
            remaining -= n
        }
    }

    static func applyFade(_ samples: inout [Float], range: Range<Int>, fadeIn: Bool) {
        let count = range.count
        guard count > 0 else { return }
        for (k, index) in range.enumerated() {
            let t = (Double(k) + 0.5) / Double(count)
            let gain = fadeIn ? sin(t * .pi / 2) : cos(t * .pi / 2)
            samples[index] *= Float(gain)
        }
    }

    /// Removes leading/trailing silence, keeping a small natural margin.
    static func trimmed(_ samples: [Float], sampleRate: Double, threshold: Float = 0.004, margin: Double = 0.04) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) > threshold }),
              let last = samples.lastIndex(where: { abs($0) > threshold }) else { return [] }
        let pad = Int(margin * sampleRate)
        let start = max(0, first - pad)
        let end = min(samples.count, last + 1 + pad)
        return Array(samples[start..<end])
    }
}
