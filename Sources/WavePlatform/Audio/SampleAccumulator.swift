import Foundation

/// Collects captured PCM in arrival order.
///
/// The audio tap fires on a real-time thread, so the samples cannot be handed
/// to an actor with `Task { await … }`: independently spawned tasks are not
/// guaranteed to run in the order they were created, which would interleave
/// buffers and scramble the recording. A plain lock keeps the append ordered
/// and finishes in microseconds.
final class SampleAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ newSamples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: newSamples)
    }

    /// Returns everything captured and empties the buffer, so the audio is
    /// released as soon as it is handed over (PRD §21).
    func drain() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let captured = samples
        samples = []
        return captured
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        samples = []
    }
}
