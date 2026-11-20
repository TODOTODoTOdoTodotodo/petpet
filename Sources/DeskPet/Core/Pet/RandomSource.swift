import Foundation

/// This object is responsible for supplying random numbers in [0, 1),
/// so behavior choices can be made reproducible in checks.
protocol RandomSource: AnyObject {
    func next() -> Double
}

extension RandomSource {
    func uniform(_ low: Double, _ high: Double) -> Double {
        low + (high - low) * next()
    }

    func chance(_ probability: Double) -> Bool {
        next() < probability
    }
}

/// This object is responsible for system-quality randomness at runtime.
final class SystemRandomSource: RandomSource {
    func next() -> Double {
        Double.random(in: 0..<1)
    }
}

/// This object is responsible for a repeatable SplitMix64 sequence used by checks.
final class SeededRandomSource: RandomSource {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
