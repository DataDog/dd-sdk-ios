import Foundation

/// Mutable interval used for periodic data uploads.
internal struct DataUploadDelay {
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
}
