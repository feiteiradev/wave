import Foundation
import Testing
@testable import WaveCore

private func tone(seconds: Double, sampleRate: Double = 16_000, amplitude: Float = 0.4) -> [Float] {
    let count = Int(seconds * sampleRate)
    return (0..<count).map { index in
        amplitude * sin(Float(index) * 2 * .pi * 220 / Float(sampleRate))
    }
}

private func silence(seconds: Double, sampleRate: Double = 16_000) -> [Float] {
    [Float](repeating: 0, count: Int(seconds * sampleRate))
}

@Suite("AudioChunker")
struct AudioChunkerTests {
    private let chunker = AudioChunker(targetSeconds: 25, maxSeconds: 30, searchWindowSeconds: 8)
    private let sampleRate: Double = 16_000

    @Test("a short recording is a single chunk")
    func shortRecordingIsOneChunk() {
        let samples = tone(seconds: 5)
        let ranges = chunker.chunkRanges(samples: samples, sampleRate: sampleRate)
        #expect(ranges == [0..<samples.count])
    }

    @Test("chunks cover the whole recording with no gaps or overlaps")
    func chunksTileTheRecording() {
        let samples = tone(seconds: 95)
        let ranges = chunker.chunkRanges(samples: samples, sampleRate: sampleRate)
        #expect(ranges.count > 1)
        #expect(ranges.first?.lowerBound == 0)
        #expect(ranges.last?.upperBound == samples.count)
        for (previous, next) in zip(ranges, ranges.dropFirst()) {
            #expect(previous.upperBound == next.lowerBound)
        }
    }

    @Test("no chunk exceeds the maximum length")
    func respectsMaximumLength() {
        let samples = tone(seconds: 95)
        let maxSamples = Int(30 * sampleRate)
        for range in chunker.chunkRanges(samples: samples, sampleRate: sampleRate) {
            #expect(range.count <= maxSamples)
        }
    }

    @Test("prefers to cut in a silent gap rather than mid-word")
    func cutsAtSilence() {
        // Speech, a clear pause at 27s, then more speech.
        var samples = tone(seconds: 27)
        samples += silence(seconds: 1)
        samples += tone(seconds: 20)
        let ranges = chunker.chunkRanges(samples: samples, sampleRate: sampleRate)
        let firstCut = Double(ranges[0].upperBound) / sampleRate
        #expect(firstCut > 27 && firstCut < 28)
    }

    @Test("an empty recording produces no chunks")
    func emptyRecording() {
        #expect(chunker.chunkRanges(samples: [], sampleRate: sampleRate).isEmpty)
    }
}

@Suite("SpeechDetector")
struct SpeechDetectorTests {
    private let detector = SpeechDetector()
    private let sampleRate: Double = 16_000

    @Test("detects speech in audible audio")
    func detectsSpeech() {
        #expect(detector.containsSpeech(samples: tone(seconds: 1), sampleRate: sampleRate))
    }

    @Test("reports no speech for pure silence")
    func rejectsSilence() {
        #expect(detector.containsSpeech(samples: silence(seconds: 3), sampleRate: sampleRate) == false)
    }

    @Test("reports no speech for an empty buffer")
    func rejectsEmpty() {
        #expect(detector.containsSpeech(samples: [], sampleRate: sampleRate) == false)
    }

    @Test("a very short utterance still counts as speech")
    func acceptsShortUtterance() {
        // "Olá." is a valid dictation — no artificial minimum (PRD §17).
        #expect(detector.containsSpeech(samples: tone(seconds: 0.3), sampleRate: sampleRate))
    }

    @Test("faint room noise does not count as speech")
    func rejectsRoomNoise() {
        let noise = tone(seconds: 2, amplitude: 0.0005)
        #expect(detector.containsSpeech(samples: noise, sampleRate: sampleRate) == false)
    }

    @Test("level is normalized and rises with amplitude")
    func levelTracksAmplitude() {
        let quiet = detector.level(samples: tone(seconds: 0.1, amplitude: 0.05)[...])
        let loud = detector.level(samples: tone(seconds: 0.1, amplitude: 0.8)[...])
        #expect(quiet < loud)
        #expect(loud <= 1)
        #expect(detector.level(samples: silence(seconds: 0.1)[...]) == 0)
    }
}
