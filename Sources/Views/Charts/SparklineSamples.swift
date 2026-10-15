import Foundation

enum SparklineSamples {
    static func displayed(history: [Double], value: Double, seed: Int, isDemo: Bool) -> [Double] {
        guard isDemo else { return history }

        // Demo curves stay in the view so synthetic readings never enter persisted history.
        let target = min(100, max(0, value))
        var current = target * 0.85
        var samples: [Double] = []
        for index in 0..<36 {
            let phase = Double(index) + Double(seed)
            let noise = sin(phase * 1.3) * 14 + cos(phase * 0.7) * 8
            current = current * 0.65 + (target + noise) * 0.35
            samples.append(min(100, max(0, current)))
        }
        samples[samples.count - 1] = target
        return samples
    }
}
