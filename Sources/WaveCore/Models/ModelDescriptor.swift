import Foundation

public enum ModelKind: String, Codable, Sendable, CaseIterable {
    case speech
    case cleanup

    var directoryName: String { rawValue }
}

/// A model Wave can install (PRD §32).
public struct ModelDescriptor: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var kind: ModelKind
    public var displayName: String
    /// Repository or variant identifier the downloader understands.
    public var repository: String
    public var approximateBytes: Int64
    /// BCP-47 tags this model is known to handle well; empty means multilingual.
    public var languages: [String]
    /// Files that must exist for the download to count as valid.
    public var requiredFiles: [String]

    public init(
        id: String,
        kind: ModelKind,
        displayName: String,
        repository: String,
        approximateBytes: Int64 = 0,
        languages: [String] = [],
        requiredFiles: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.displayName = displayName
        self.repository = repository
        self.approximateBytes = approximateBytes
        self.languages = languages
        self.requiredFiles = requiredFiles
    }
}

/// What the user sees while a model is being installed (PRD §35).
public enum ModelInstallPhase: Sendable, Equatable {
    case downloading(fraction: Double)
    case validating
    case activating
    case removingPrevious
    case finished
    case retrying
    case failed(needsManualRetry: Bool)
}

public enum ModelError: Error, Sendable, Equatable {
    case downloadFailed
    case validationFailed(missingFile: String?)
    case notInstalled
}
