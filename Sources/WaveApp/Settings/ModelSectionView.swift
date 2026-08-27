import SwiftUI
import WaveCore
import WavePlatform

/// The Model Manager UI shared by the Speech and Cleanup sections (PRD §32).
struct ModelSectionView: View {
    let kind: ModelKind
    let title: String
    let footer: String
    var allowsRemoval: Bool = false

    @EnvironmentObject private var model: AppModel

    private var installed: ModelDescriptor? {
        kind == .speech ? model.installedSpeechModel : model.installedCleanupModel
    }

    var body: some View {
        Form {
            Section(title) {
                ForEach(ModelCatalog.models(of: kind)) { descriptor in
                    ModelRow(
                        descriptor: descriptor,
                        isInstalled: installed?.id == descriptor.id,
                        phase: model.installPhase[descriptor.id],
                        isBusy: isBusy
                    ) {
                        Task { await model.install(descriptor) }
                    }
                }
            }

            if let phase = activePhase {
                Section { InstallPhaseView(phase: phase) }
            }

            if allowsRemoval, installed != nil {
                Section {
                    Button("Remove Cleanup Model", role: .destructive) {
                        Task { await model.uninstallCleanupModel() }
                    }
                }
            }

            Section {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await model.refreshInstalledModels() }
    }

    /// The phase of whichever model of this kind is mid-install.
    private var activePhase: ModelInstallPhase? {
        ModelCatalog.models(of: kind).compactMap { model.installPhase[$0.id] }.first
    }

    private var isBusy: Bool {
        switch activePhase {
        case .downloading, .validating, .activating, .removingPrevious, .retrying: true
        default: false
        }
    }
}

private struct ModelRow: View {
    let descriptor: ModelDescriptor
    let isInstalled: Bool
    let phase: ModelInstallPhase?
    let isBusy: Bool
    let install: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(descriptor.displayName)
                Text(Self.sizeFormatter.string(fromByteCount: descriptor.approximateBytes))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isInstalled {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.titleAndIcon)
                    .font(.caption)
            } else {
                Button(needsManualRetry ? "Retry" : "Install", action: install)
                    .disabled(isBusy)
            }
        }
    }

    private var needsManualRetry: Bool {
        if case .failed = phase { return true }
        return false
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

private struct InstallPhaseView: View {
    let phase: ModelInstallPhase

    var body: some View {
        switch phase {
        case let .downloading(fraction):
            ProgressView(value: fraction) { Text("Downloading…") }
        case .validating:
            ProgressView { Text("Validating…") }
        case .activating:
            ProgressView { Text("Activating…") }
        case .removingPrevious:
            ProgressView { Text("Removing the previous model…") }
        case .retrying:
            Label("Download failed — retrying once.", systemImage: "arrow.clockwise")
                .foregroundStyle(.orange)
        case .failed:
            Label("Download failed. The previous model is still installed.", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case .finished:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}
