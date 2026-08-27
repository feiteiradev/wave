import AppKit
import SwiftUI
import WaveCore

/// Click, then press the combination you want (PRD §14).
struct HotkeyRecorderRow: View {
    let title: String
    @Binding var binding: HotkeyBinding

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            Button(isRecording ? "Press keys…" : binding.displayString) {
                isRecording ? stopRecording() : startRecording()
            }
            .frame(minWidth: 120)
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // A modifier-less hotkey would swallow ordinary typing.
            let modifiers = Self.modifiers(from: event.modifierFlags)
            guard !modifiers.isEmpty else { return nil }
            binding = HotkeyBinding(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private static func modifiers(from flags: NSEvent.ModifierFlags) -> HotkeyBinding.Modifiers {
        var result: HotkeyBinding.Modifiers = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.shift) { result.insert(.shift) }
        return result
    }
}
