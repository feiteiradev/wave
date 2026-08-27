import AppKit
import Combine
import SwiftUI
import WaveCore

/// Hosts the HUD in a borderless panel positioned around the notch (PRD §26).
///
/// The panel is only ordered in while there is something to show; the rest of
/// the time Wave has no windows on screen at all.
@MainActor
final class NotchHUDController {
    private let model: AppModel
    private var panel: NSPanel?
    private var hostingView: NSHostingView<NotchHUDView>?
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model

        model.$hud
            .removeDuplicates()
            .sink { [weak self] state in self?.update(for: state) }
            .store(in: &cancellables)

        // Reposition when the display arrangement changes.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &cancellables)
    }

    private func update(for state: HUDState) {
        guard state.isVisible else {
            panel?.orderOut(nil)
            return
        }
        let panel = existingPanel()
        let root = NotchHUDView(state: state, waveform: model.waveform)
        if let hostingView {
            // Updating the root view rather than replacing the hosting view
            // preserves SwiftUI's view identity, so the HUD's transitions
            // actually run instead of snapping — this is hit on every level
            // update while recording.
            hostingView.rootView = root
        } else {
            let view = NSHostingView(rootView: root)
            hostingView = view
            panel.contentView = view
        }
        reposition()
        panel.orderFrontRegardless()
    }

    private func existingPanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        self.panel = panel
        return panel
    }

    /// Centres the HUD horizontally and tucks it under the menu bar. On a Mac
    /// with a notch, `safeAreaInsets.top` is the notch height, so the HUD sits
    /// just below it and reads as wrapping around it.
    private func reposition() {
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        let notchHeight = screen.safeAreaInsets.top
        let topInset = notchHeight > 0 ? notchHeight : screen.frame.maxY - screen.visibleFrame.maxY

        let origin = CGPoint(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - topInset - size.height - 2
        )
        panel.setFrameOrigin(origin)
    }
}
