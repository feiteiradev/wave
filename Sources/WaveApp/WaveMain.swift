import AppKit

@main
enum WaveMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = WaveAppDelegate()
        application.delegate = delegate
        // The delegate is the only strong reference AppKit does not keep.
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
