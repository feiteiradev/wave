import SwiftUI
import WaveCore
import WavePlatform

/// First-run setup (PRD §31). Four rows, not a long wizard.
///
/// Get Started stays disabled until a speech model is installed and validated —
/// Wave cannot dictate without one (PRD §31.2).
struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    let finish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Wave").font(.largeTitle.bold())
                Text("Speak naturally. Wave handles the rest.")
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRow(permission: permission)
                }
                hotkeyRow
                speechModelRow
            }

            Spacer()

            HStack {
                Text("Your voice never leaves this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Get Started", action: finish)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.installedSpeechModel == nil)
            }
        }
        .padding(28)
        .frame(width: 520, height: 460)
        .task {
            model.refreshPermissions()
            await model.refreshInstalledModels()
        }
    }

    private var hotkeyRow: some View {
        OnboardingRow(
            title: "Hotkeys",
            detail: "Clean \(model.preferences.cleanHotkey.displayString)   ·   Raw \(model.preferences.rawHotkey.displayString)",
            isDone: model.hotkeyConflicts.isEmpty
        ) {
            EmptyView()
        }
    }

    @ViewBuilder
    private var speechModelRow: some View {
        OnboardingRow(
            title: "Speech Model",
            detail: model.installedSpeechModel?.displayName
                ?? ModelCatalog.defaultSpeechModel.displayName,
            isDone: model.installedSpeechModel != nil
        ) {
            if model.installedSpeechModel == nil {
                switch model.installPhase[ModelCatalog.defaultSpeechModel.id] {
                case let .downloading(fraction):
                    ProgressView(value: fraction).frame(width: 90)
                case .validating, .activating, .removingPrevious:
                    ProgressView().controlSize(.small)
                case .retrying:
                    Text("Retrying…").font(.caption).foregroundStyle(.orange)
                case .failed:
                    Button("Retry") {
                        Task { await model.install(ModelCatalog.defaultSpeechModel) }
                    }
                default:
                    Button("Download") {
                        Task { await model.install(ModelCatalog.defaultSpeechModel) }
                    }
                }
            }
        }
    }
}

private struct PermissionRow: View {
    let permission: Permission
    @EnvironmentObject private var model: AppModel

    var body: some View {
        OnboardingRow(
            title: permission.title,
            detail: permission.explanation,
            isDone: model.permissions[permission] == true
        ) {
            if model.permissions[permission] != true {
                Button("Allow…") {
                    Task {
                        await model.requestPermission(permission)
                        if model.permissions[permission] != true {
                            Permissions.openSettings(for: permission)
                        }
                    }
                }
            }
        }
    }
}

private struct OnboardingRow<Accessory: View>: View {
    let title: String
    let detail: String
    let isDone: Bool
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isDone ? .green : .secondary)
                .font(.title3)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)
            accessory()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
    }
}
