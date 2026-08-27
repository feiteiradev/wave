import Foundation

/// Local technical logs with a hard retention ceiling (PRD §37.2).
///
/// One file per day, so retention is a matter of deleting whole files. Both
/// limits apply at once: nothing older than `maximumAge`, and no more than
/// `maximumTotalBytes` in aggregate, oldest deleted first.
public final class DiagnosticsLogger: @unchecked Sendable {
    public struct Retention: Sendable {
        public var maximumAge: TimeInterval
        public var maximumTotalBytes: Int64

        public init(maximumAge: TimeInterval = 7 * 24 * 3600, maximumTotalBytes: Int64 = 10 * 1_024 * 1_024) {
            self.maximumAge = maximumAge
            self.maximumTotalBytes = maximumTotalBytes
        }
    }

    public let directory: URL
    private let retention: Retention
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private let fileManager = FileManager.default

    private lazy var timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.timeZone = .current
        return formatter
    }()

    private lazy var dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    public init(directory: URL, retention: Retention = Retention(), now: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.retention = retention
        self.now = now
    }

    public func log(_ event: DiagnosticEvent) {
        let date = now()
        let line = "[\(timestampFormatter.string(from: date))] \(event.message)\n"
        lock.lock(); defer { lock.unlock() }
        write(line, on: date)
        enforceRetentionLocked()
    }

    public func currentLogFileURL(on date: Date? = nil) -> URL {
        directory.appendingPathComponent("wave-\(dayFormatter.string(from: date ?? now())).log")
    }

    public func logFileURLs() -> [URL] {
        lock.lock(); defer { lock.unlock() }
        return existingLogFilesLocked().map(\.url)
    }

    public func enforceRetention() {
        lock.lock(); defer { lock.unlock() }
        enforceRetentionLocked()
    }

    // MARK: - Private

    private func write(_ line: String, on date: Date) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = currentLogFileURL(on: date)
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    private struct LogFile {
        let url: URL
        let day: Date
        let size: Int64
    }

    private func existingLogFilesLocked() -> [LogFile] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return contents.compactMap { url -> LogFile? in
            let name = url.lastPathComponent
            guard name.hasPrefix("wave-"), name.hasSuffix(".log") else { return nil }
            let stamp = String(name.dropFirst("wave-".count).dropLast(".log".count))
            guard let day = dayFormatter.date(from: stamp) else { return nil }
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            return LogFile(url: url, day: day, size: size)
        }
        .sorted { $0.day < $1.day }
    }

    private func enforceRetentionLocked() {
        var files = existingLogFilesLocked()
        let cutoff = now().addingTimeInterval(-retention.maximumAge)

        // Age limit. The current day's file is never dropped.
        let today = dayFormatter.string(from: now())
        files.removeAll { file in
            guard file.day < cutoff, dayFormatter.string(from: file.day) != today else { return false }
            try? fileManager.removeItem(at: file.url)
            return true
        }

        // Size limit, oldest first.
        var total = files.reduce(Int64(0)) { $0 + $1.size }
        while total > retention.maximumTotalBytes, files.count > 1, let oldest = files.first {
            try? fileManager.removeItem(at: oldest.url)
            total -= oldest.size
            files.removeFirst()
        }

        // A single busy day can exceed the cap on its own, and that file is the
        // one being written to — so trim it from the front instead of deleting it.
        if total > retention.maximumTotalBytes, let newest = files.last {
            truncateFromFront(newest.url, to: retention.maximumTotalBytes)
        }
    }

    /// Drops whole lines from the start of the file until it fits.
    private func truncateFromFront(_ url: URL, to limit: Int64) {
        guard limit > 0, let data = try? Data(contentsOf: url), Int64(data.count) > limit else { return }
        let excess = data.count - Int(limit)
        // Cut at the first line break at or after the excess, so no partial line survives.
        let newline = UInt8(ascii: "\n")
        var cut = excess
        while cut < data.count, data[cut] != newline { cut += 1 }
        if cut < data.count { cut += 1 }
        try? data.suffix(from: cut).write(to: url, options: .atomic)
    }
}
