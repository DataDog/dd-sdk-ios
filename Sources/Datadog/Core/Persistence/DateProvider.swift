import Foundation

/// Interface for date provider used for files orchestration.
internal protocol DateProvider {
    func currentDate() -> Date
}

internal struct SystemDateProvider: DateProvider {
    @inlinable
    func currentDate() -> Date { return Date() }
}
