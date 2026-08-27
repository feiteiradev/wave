import Foundation
import Testing
@testable import WavePlatform

private func makeTemporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("wave-flatten-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Download layout")
struct DownloadLayoutTests {
    /// The hubs deliver models nested under a repo path; the installed layout
    /// has to be flat or the engines will not find the model files.
    @Test("lifts nested download contents into the staging root")
    func flattensNestedDownload() throws {
        let staging = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }

        let nested = staging.appendingPathComponent("models/argmaxinc/whisper", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("weights".utf8).write(to: nested.appendingPathComponent("model.bin"))
        try Data("{}".utf8).write(to: nested.appendingPathComponent("config.json"))

        try WhisperModelDownloader.flatten(nested, into: staging)

        #expect(FileManager.default.fileExists(atPath: staging.appendingPathComponent("model.bin").path))
        #expect(FileManager.default.fileExists(atPath: staging.appendingPathComponent("config.json").path))
    }

    @Test("overwrites a file left by a previous attempt")
    func overwritesExistingFile() throws {
        let staging = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }

        try Data("stale".utf8).write(to: staging.appendingPathComponent("model.bin"))
        let nested = staging.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("fresh".utf8).write(to: nested.appendingPathComponent("model.bin"))

        try WhisperModelDownloader.flatten(nested, into: staging)

        let contents = try String(contentsOf: staging.appendingPathComponent("model.bin"), encoding: .utf8)
        #expect(contents == "fresh")
    }

    @Test("a download already at the root is left alone")
    func alreadyFlatIsNoOp() throws {
        let staging = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: staging) }
        try Data("weights".utf8).write(to: staging.appendingPathComponent("model.bin"))

        try WhisperModelDownloader.flatten(staging, into: staging)

        #expect(FileManager.default.fileExists(atPath: staging.appendingPathComponent("model.bin").path))
    }
}

@Suite("SampleAccumulator")
struct SampleAccumulatorTests {
    @Test("keeps appended buffers in order")
    func keepsOrder() {
        let accumulator = SampleAccumulator()
        accumulator.append([1, 2])
        accumulator.append([3, 4])
        #expect(accumulator.drain() == [1, 2, 3, 4])
    }

    @Test("draining empties the buffer so audio is not retained")
    func drainEmpties() {
        let accumulator = SampleAccumulator()
        accumulator.append([1, 2, 3])
        #expect(accumulator.drain() == [1, 2, 3])
        #expect(accumulator.drain().isEmpty)
    }

    @Test("reset discards everything captured")
    func resetDiscards() {
        let accumulator = SampleAccumulator()
        accumulator.append([1, 2, 3])
        accumulator.reset()
        #expect(accumulator.drain().isEmpty)
    }

    @Test("concurrent appends never lose samples")
    func concurrentAppendsAreSafe() async {
        let accumulator = SampleAccumulator()
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<100 {
                group.addTask { accumulator.append([1, 1, 1, 1]) }
            }
        }
        #expect(accumulator.drain().count == 400)
    }
}
