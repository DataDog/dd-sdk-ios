import Foundation

/// Mutable interval used for periodic logs upload.
internal struct LogsUploadDelay {
    private let defaultDelay: TimeInterval
    private let minDelay: TimeInterval
    private let maxDelay: TimeInterval
    private let decreaseFactor: Double

    private var delay: TimeInterval

    init(`default`: TimeInterval, min: TimeInterval, max: TimeInterval, decreaseFactor: Double) {
        self.defaultDelay = `default`
        self.minDelay = min
        self.maxDelay = max
        self.decreaseFactor = decreaseFactor
        self.delay = `default`
    }

    mutating func nextUploadDelay() -> TimeInterval {
        defer {
            if delay == maxDelay {
                delay = defaultDelay
            }
        }
        return delay
    }

    mutating func decrease() {
        delay = max(minDelay, delay * decreaseFactor)
    }

    mutating func increaseOnce() {
        delay = maxDelay
    }

    /// Default configuration for `LogsUploadDelay`.
    static let `default`: LogsUploadDelay = LogsUploadDelay(
        default: LogsFileStrategy.Constants.defaultLogsUploadDelay,
        min: LogsFileStrategy.Constants.minLogsUploadDelay,
        max: LogsFileStrategy.Constants.maxLogsUploadDelay,
        decreaseFactor: LogsFileStrategy.Constants.logsUploadDelayDecreaseFactor
    )
}
