import Foundation
import WaveCore

/// The models Wave offers in the Model Manager (PRD §32, §9.2, §34).
///
/// Variant names are the folder names published in
/// `argmaxinc/whisperkit-coreml`; cleanup models are `mlx-community`
/// repositories. Only one of each kind is installed at a time (PRD §44).
public enum ModelCatalog {
    public static let whisperRepository = "argmaxinc/whisperkit-coreml"

    /// Multilingual variants only. The `.en` and `distil-*` builds are English
    /// -only and would be useless for the PT-PT target (PRD §41).
    public static let speechModels: [ModelDescriptor] = [
        ModelDescriptor(
            id: "openai_whisper-large-v3-v20240930_turbo",
            kind: .speech,
            displayName: "Whisper Large v3 Turbo",
            repository: whisperRepository,
            approximateBytes: 1_600_000_000,
            languages: [],
            requiredFiles: []
        ),
        ModelDescriptor(
            id: "openai_whisper-large-v3",
            kind: .speech,
            displayName: "Whisper Large v3",
            repository: whisperRepository,
            approximateBytes: 3_100_000_000,
            languages: [],
            requiredFiles: []
        ),
        ModelDescriptor(
            id: "openai_whisper-medium",
            kind: .speech,
            displayName: "Whisper Medium",
            repository: whisperRepository,
            approximateBytes: 1_500_000_000,
            languages: [],
            requiredFiles: []
        ),
        ModelDescriptor(
            id: "openai_whisper-small",
            kind: .speech,
            displayName: "Whisper Small",
            repository: whisperRepository,
            approximateBytes: 480_000_000,
            languages: [],
            requiredFiles: []
        ),
    ]

    public static let cleanupModels: [ModelDescriptor] = [
        ModelDescriptor(
            id: "Qwen2.5-3B-Instruct-4bit",
            kind: .cleanup,
            displayName: "Qwen 2.5 3B Instruct (4-bit)",
            repository: "mlx-community/Qwen2.5-3B-Instruct-4bit",
            approximateBytes: 1_700_000_000,
            languages: [],
            requiredFiles: ["config.json"]
        ),
        ModelDescriptor(
            id: "Qwen3-4B-4bit",
            kind: .cleanup,
            displayName: "Qwen 3 4B (4-bit)",
            repository: "mlx-community/Qwen3-4B-4bit",
            approximateBytes: 2_300_000_000,
            languages: [],
            requiredFiles: ["config.json"]
        ),
        ModelDescriptor(
            id: "gemma-3-4b-it-4bit",
            kind: .cleanup,
            displayName: "Gemma 3 4B Instruct (4-bit)",
            repository: "mlx-community/gemma-3-4b-it-4bit",
            approximateBytes: 2_400_000_000,
            languages: [],
            requiredFiles: ["config.json"]
        ),
    ]

    /// Suggested during onboarding: multilingual, and the fastest of the
    /// large-v3 family (PRD §31.2). The final PT-PT choice is a benchmarking
    /// question the PRD leaves open (PRD §45).
    public static let defaultSpeechModel = speechModels[0]
    public static let defaultCleanupModel = cleanupModels[0]

    public static func models(of kind: ModelKind) -> [ModelDescriptor] {
        kind == .speech ? speechModels : cleanupModels
    }

    public static func model(id: String) -> ModelDescriptor? {
        (speechModels + cleanupModels).first { $0.id == id }
    }

    /// The languages Wave offers (PRD §10). Portuguese (Portugal) first: it is
    /// the default and the primary quality target.
    public static let languages: [(code: String, name: String)] = [
        ("pt-PT", "Português (Portugal)"),
        ("pt-BR", "Português (Brasil)"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("es-ES", "Español"),
        ("fr-FR", "Français"),
        ("de-DE", "Deutsch"),
        ("it-IT", "Italiano"),
    ]
}
