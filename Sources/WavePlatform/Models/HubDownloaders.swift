import Foundation
import Hub
import WaveCore
import WhisperKit

/// Downloads WhisperKit Core ML models (PRD §32).
///
/// Network access happens only here, during explicit model management — never
/// during dictation (PRD §20.2).
public struct WhisperModelDownloader: WaveCore.ModelDownloader {
    public init() {}

    public func download(
        _ descriptor: ModelDescriptor,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let downloaded = try await WhisperKit.download(
            variant: descriptor.id,
            downloadBase: destination,
            from: descriptor.repository,
            progressCallback: { progress($0.fractionCompleted) }
        )
        // WhisperKit nests the variant under its repo path; lift the model
        // files to the top of the staging directory so the installed layout is
        // just `…/speech/<id>/<model files>`.
        try Self.flatten(downloaded, into: destination)
    }

    static func flatten(_ source: URL, into destination: URL) throws {
        guard source.standardizedFileURL != destination.standardizedFileURL else { return }
        let fileManager = FileManager.default
        for item in try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            try? fileManager.removeItem(at: target)
            try fileManager.moveItem(at: item, to: target)
        }
    }
}

/// Downloads an MLX cleanup model from the Hugging Face hub (PRD §34).
public struct MLXModelDownloader: WaveCore.ModelDownloader {
    public init() {}

    public func download(
        _ descriptor: ModelDescriptor,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let hub = HubApi(downloadBase: destination)
        let repository = Hub.Repo(id: descriptor.repository, type: .models)
        let downloaded = try await hub.snapshot(
            from: repository,
            matching: ["*.safetensors", "*.json", "*.txt", "*.model"]
        ) { fileProgress in
            progress(fileProgress.fractionCompleted)
        }
        try WhisperModelDownloader.flatten(downloaded, into: destination)
    }
}
