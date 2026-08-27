import AppKit
import SwiftUI
import WaveCore
import WavePlatform

@MainActor
final class WaveAppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()
    private var menuBar: MenuBarController?
    private var hud: NotchHUDController?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A menu-bar utility, not an app with a Dock icon (PRD §7 G7, §24).
        NSApp.setActivationPolicy(.accessory)

        hud = NotchHUDController(model: model)
        menuBar = MenuBarController(model: model) { [weak self] in
            self?.showSettings()
        }

        Task {
            await model.start()
            if !model.preferences.hasCompletedOnboarding {
                showOnboarding()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Closing Settings must not quit a menu-bar utility.
        false
    }

    private func showSettings() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let window = Self.makeWindow(
            title: "Wave Settings",
            content: SettingsView().environmentObject(model)
        )
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showOnboarding() {
        guard onboardingWindow == nil else { return }
        let window = Self.makeWindow(
            title: "Welcome to Wave",
            content: OnboardingView(finish: { [weak self] in
                self?.model.completeOnboarding()
                self?.onboardingWindow?.close()
                self?.onboardingWindow = nil
            }).environmentObject(model)
        )
        onboardingWindow = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func makeWindow(title: String, content: some View) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: content)
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
