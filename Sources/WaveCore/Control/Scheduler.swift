import Foundation

/// Delayed work (HUD auto-hide, clipboard restore), injected so tests do not
/// have to wait in real time.
public protocol Scheduler: Sendable {
    func schedule(after seconds: Double, _ work: @escaping @Sendable () async -> Void)
}

public struct TaskScheduler: Scheduler {
    public init() {}

    public func schedule(after seconds: Double, _ work: @escaping @Sendable () async -> Void) {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            await work()
        }
    }
}
