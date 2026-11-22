import Foundation

/// Supertonic voice style embedding (`voice_styles/F1.json` …).
struct VoiceStyle: Sendable {
    let ttl: [Float]
    let ttlShape: [Int]
    let dp: [Float]
    let dpShape: [Int]

    static func load(from url: URL) throws -> VoiceStyle {
        let data = try Data(contentsOf: url)
        return try parse(data)
    }

    static func parse(_ data: Data) throws -> VoiceStyle {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SupertonicError.invalidModel("style vocal illisible")
        }
        let (ttl, ttlShape) = try tensor(named: "style_ttl", in: root)
        let (dp, dpShape) = try tensor(named: "style_dp", in: root)
        return VoiceStyle(ttl: ttl, ttlShape: ttlShape, dp: dp, dpShape: dpShape)
    }

    private static func tensor(named key: String, in root: [String: Any]) throws -> ([Float], [Int]) {
        guard let entry = root[key] as? [String: Any],
              let rawDims = entry["dims"] as? [Any],
              let payload = entry["data"] else {
            throw SupertonicError.invalidModel("champ \(key) manquant")
        }
        let dims = rawDims.compactMap(number).map { Int($0) }
        var values: [Float] = []
        values.reserveCapacity(dims.reduce(1, *))
        flatten(payload, into: &values)
        guard dims.count == rawDims.count, values.count == dims.reduce(1, *) else {
            throw SupertonicError.invalidModel("dimensions incohérentes pour \(key)")
        }
        return (values, dims)
    }

    private static func number(_ any: Any) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func flatten(_ any: Any, into out: inout [Float]) {
        if let array = any as? [Any] {
            for element in array { flatten(element, into: &out) }
        } else if let value = number(any) {
            out.append(Float(value))
        }
    }
}

/// Deterministic Gaussian noise for the flow-matching sampler. Using a seed per
/// project means that regenerating the same script gives the same performance.
struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        // SplitMix64
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Standard normal samples (Box–Muller).
    mutating func gaussian(count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: count)
        var i = 0
        while i < count {
            let u1 = max(Double.random(in: 0..<1, using: &self), 1e-12)
            let u2 = Double.random(in: 0..<1, using: &self)
            let radius = (-2 * log(u1)).squareRoot()
            out[i] = Float(radius * cos(2 * .pi * u2))
            if i + 1 < count { out[i + 1] = Float(radius * sin(2 * .pi * u2)) }
            i += 2
        }
        return out
    }
}
