import AppKit
import Combine
import WaveCore

/// The persistent status surface (PRD §24). Everything else in Wave is
/// temporary; this is the one thing always on screen.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let openSettings: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    private let statusMenuItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")
    private let recordMenuItem = NSMenuItem(title: "Start Recording", action: nil, keyEquivalent: "")

    init(model: AppModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "waveform",
            accessibilityDescription: "Wave"
        )
        statusItem.button?.image?.isTemplate = true
        statusItem.menu = buildMenu()

        model.$statusMessage
            .sink { [weak self] message in self?.statusMenuItem.title = message }
            .store(in: &cancellables)

        model.$dictationState
            .sink { [weak self] state in self?.updateForState(state) }
            .store(in: &cancellables)
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        recordMenuItem.target = self
        recordMenuItem.action = #selector(toggleRecording)
        menu.addItem(recordMenuItem)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Wave", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func updateForState(_ state: DictationState) {
        switch state {
        case .idle:
            recordMenuItem.title = "Start Recording"
            recordMenuItem.isEnabled = true
        case .recording:
            recordMenuItem.title = "Stop Recording"
            recordMenuItem.isEnabled = true
        case .processing:
            // One dictation at a time (PRD §15).
            recordMenuItem.title = "Start Recording"
            recordMenuItem.isEnabled = false
        }
        if case .processing = state {
            statusItem.button?.appearsDisabled = true
        } else {
            statusItem.button?.appearsDisabled = false
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        model.refreshMicrophones()
    }

    @objc private func toggleRecording() {
        model.toggleRecordingFromMenu()
    }

    @objc private func showSettings() {
        openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
