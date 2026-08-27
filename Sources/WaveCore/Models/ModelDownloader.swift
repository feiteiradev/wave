import Foundation

/// Fetches a model into a staging directory. Implemented over WhisperKit and
/// the Hugging Face hub in `WavePlatform`; faked in tests.
public protocol ModelDownloader: Sendable {
    /// Downloads `descriptor` into `destination`, reporting 0...1 progress.
    func download(
        _ descriptor: ModelDescriptor,
        to destination: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}
