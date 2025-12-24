import Foundation

struct DetectedChord: Equatable {
    let name: String
    let confidence: Float
}

final class ChordDetectionEngine {
    private let sampleRate: Double
    private let frameSize: Int
    private let detector: ChordDetectorWrapper

    init(sampleRate: Double, frameSize: Int) {
        self.sampleRate = sampleRate
        self.frameSize = frameSize
        self.detector = ChordDetectorWrapper(frameSize: frameSize, sampleRate: sampleRate)
    }

    func analyze(samples: [Float]) -> DetectedChord? {
        guard samples.count >= frameSize else { return nil }
        let frame = Array(samples.prefix(frameSize))
        let numbers = frame.map { NSNumber(value: $0) }
        guard let result = detector.detectChord(withAudioFrame: numbers) else { return nil }

        let root = result["rootNote"]?.intValue ?? -1
        let quality = result["quality"]?.intValue ?? -1
        let intervals = result["intervals"]?.intValue ?? 0
        let confidence = result["confidence"]?.floatValue ?? 0
        guard let name = chordName(root: root, quality: quality, intervals: intervals) else { return nil }
        return DetectedChord(name: name, confidence: confidence)
    }

    private func chordName(root: Int, quality: Int, intervals: Int) -> String? {
        let roots = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        guard root >= 0 && root < roots.count else { return nil }

        let suffix: String
        switch quality {
        case 0: // Minor
            suffix = intervals == 7 ? "m7" : "m"
        case 1: // Major
            suffix = intervals == 7 ? "maj7" : ""
        case 2: // Suspended
            suffix = intervals == 2 ? "sus2" : "sus4"
        case 3: // Dominant
            suffix = "7"
        case 4: // Diminished 5th
            suffix = "dim"
        case 5: // Augmented 5th
            suffix = "aug"
        default:
            return nil
        }
        return roots[root] + suffix
    }
}
