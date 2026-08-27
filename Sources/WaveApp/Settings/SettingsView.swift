import SwiftUI
import WaveCore
import WavePlatform

/// The native Settings window (PRD §30). The menu bar stays minimal; anything
/// configurable lives here.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            DictationSettingsView()
                .tabItem { Label("Dictation", systemImage: "mic") }
            SpeechRecognitionSettingsView()
                .tabItem { Label("Speech", systemImage: "waveform") }
            CleanupSettingsView()
                .tabItem { Label("Cleanup", systemImage: "wand.and.sparkles") }
            VocabularySettingsView()
                .tabItem { Label("Vocabulary", systemImage: "character.book.closed") }
            DiagnosticsSettingsView()
                .tabItem { Label("Diagnostics", systemImage: "stethoscope") }
            AboutView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
    }
}

struct GeneralSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch Wave at Login", isOn: $model.preferences.launchAtLogin)
            }
            Section("Permissions") {
                ForEach(Permission.allCases, id: \.self) { permission in
                    HStack {
                        Label(permission.title, systemImage: model.permissions[permission] == true
                            ? "checkmark.circle.fill" : "exclamationmark.circle")
                            .foregroundStyle(model.permissions[permission] == true ? .green : .orange)
                        Spacer()
                        if model.permissions[permission] != true {
                            Button("Open Settings…") {
                                Permissions.openSettings(for: permission)
                            }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshPermissions() }
    }
}

struct DictationSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Activation") {
                Picker("Mode", selection: $model.preferences.activationMode) {
                    Text("Push to talk").tag(ActivationMode.pushToTalk)
                    Text("Toggle").tag(ActivationMode.toggle)
                }
                .pickerStyle(.radioGroup)
                Text("Applies to both hotkeys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Hotkeys") {
                HotkeyRecorderRow(title: "Clean", binding: $model.preferences.cleanHotkey)
                HotkeyRecorderRow(title: "Raw", binding: $model.preferences.rawHotkey)
                if !model.hotkeyConflicts.isEmpty {
                    Label(
                        "Another app is already using \(model.hotkeyConflicts.map(\.rawValue).joined(separator: " and ")).",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Section("Microphone") {
                Picker("Input", selection: $model.preferences.microphoneUniqueID) {
                    Text("System Default").tag(String?.none)
                    ForEach(model.microphones) { device in
                        Text(device.name).tag(String?.some(device.uniqueID))
                    }
                }
            }

            Section("Language") {
                Picker("Language", selection: $model.preferences.language) {
                    ForEach(ModelCatalog.languages, id: \.code) { language in
                        Text(language.name).tag(language.code)
                    }
                }
                Text("One language is active at a time. Wave does not detect it automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.refreshMicrophones() }
    }
}

struct SpeechRecognitionSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ModelSectionView(
            kind: .speech,
            title: "Speech Model",
            footer: "One speech model is installed at a time. The current model keeps working until a replacement has downloaded and been validated."
        )
    }
}

struct CleanupSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle("Use a local model for Clean", isOn: $model.preferences.cleanupLLMEnabled)
                    Text("Clean also works without a model — punctuation and capitalization rules still run.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .frame(height: 110)

            ModelSectionView(
                kind: .cleanup,
                title: "Cleanup Model",
                footer: "Loaded on demand and unloaded again after a few minutes of inactivity.",
                allowsRemoval: true
            )
        }
    }
}

struct DiagnosticsSettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Text("Wave keeps local technical logs: durations, model names and which insertion method was used. They never contain audio, transcribed text or clipboard contents.")
                    .font(.callout)
                Text("Logs are kept for at most 7 days or 10 MB, whichever comes first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Open Logs") { model.openLogsFolder() }
            }
        }
        .formStyle(.grouped)
    }
}

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 42))
                .foregroundStyle(.tint)
            Text("Wave").font(.title.bold())
            Text("Speak naturally. Wave handles the rest.")
                .foregroundStyle(.secondary)
            Text("Your voice stays on this Mac. Dictation needs no internet connection.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
