import Foundation

/// A tiny synchronous mutex box.
///
/// Test fakes need mutable counters that are safe to touch from async code.
/// Calling `NSLock.lock()` directly inside an `async` body is an error in the
/// Swift 6 language mode, so the locking is confined to these synchronous
/// methods and async callers just call `withValue`.
final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) { self.value = value }

    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }

    var current: Value { withValue { $0 } }
}
