import Foundation

/// Splits a long recording into STT-sized chunks (PRD §11.3, AC6).
///
/// Cuts are placed at the quietest point inside a window around the target
/// length rather than at a fixed offset, so a chunk boundary lands between
/// words instead of through one. Everything stays in memory; nothing is
/// written to disk (PRD §21).
public struct AudioChunker: Sendable {
    /// Preferred chunk length. Cuts are searched for around this point.
    public let targetSeconds: Double
    /// Hard ceiling — a cut is forced here even if no quiet point was found.
    public let maxSeconds: Double
    /// How far before `maxSeconds` the search for a quiet point begins.
    public let searchWindowSeconds: Double

    public init(targetSeconds: Double = 25, maxSeconds: Double = 30, searchWindowSeconds: Double = 8) {
        precondition(targetSeconds > 0 && maxSeconds >= targetSeconds && searchWindowSeconds > 0)
        self.targetSeconds = targetSeconds
        self.maxSeconds = maxSeconds
        self.searchWindowSeconds = searchWindowSeconds
    }

    /// Sample ranges covering the whole recording, in order, without gaps.
    public func chunkRanges(sampleCount: Int, sampleRate: Double) -> [Range<Int>] {
        guard sampleCount > 0, sampleRate > 0 else { return [] }
        let maxSamples = Int(maxSeconds * sampleRate)
        guard sampleCount > maxSamples else { return [0..<sampleCount] }

        var ranges: [Range<Int>] = []
        var start = 0
        while start < sampleCount {
            let remaining = sampleCount - start
            if remaining <= maxSamples {
                ranges.append(start..<sampleCount)
                break
            }
            ranges.append(start..<(start + maxSamples))
            start += maxSamples
        }
        return ranges
    }

    /// As `chunkRanges(sampleCount:sampleRate:)`, but nudges each boundary to
    /// the quietest short window it can find nearby.
    public func chunkRanges(samples: [Float], sampleRate: Double) -> [Range<Int>] {
        guard !samples.isEmpty, sampleRate > 0 else { return [] }
        let maxSamples = Int(maxSeconds * sampleRate)
        guard samples.count > maxSamples else { return [0..<samples.count] }

        let targetSamples = Int(targetSeconds * sampleRate)
        let searchSamples = min(Int(searchWindowSeconds * sampleRate), maxSamples - 1)
        let probe = max(1, Int(0.05 * sampleRate))

        var ranges: [Range<Int>] = []
        var start = 0
        while start < samples.count {
            let remaining = samples.count - start
            if remaining <= maxSamples {
                ranges.append(start..<samples.count)
                break
            }
            let hardEnd = start + maxSamples
            let searchStart = max(start + probe, min(start + targetSamples, hardEnd - searchSamples))
            let cut = quietestBoundary(in: samples, from: searchStart, to: hardEnd, probe: probe) ?? hardEnd
            ranges.append(start..<cut)
            start = cut
        }
        return ranges
    }

    /// Index of the centre of the lowest-energy `probe`-wide window in the range.
    private func quietestBoundary(in samples: [Float], from lower: Int, to upper: Int, probe: Int) -> Int? {
        guard lower < upper, upper <= samples.count else { return nil }
        var bestIndex: Int?
        var bestEnergy = Float.greatestFiniteMagnitude
        var index = lower
        while index + probe <= upper {
            var energy: Float = 0
            for offset in index..<(index + probe) { energy += abs(samples[offset]) }
            if energy < bestEnergy {
                bestEnergy = energy
                bestIndex = index + probe / 2
            }
            index += probe
        }
        return bestIndex
    }
}
