import Foundation

/// File creation date is used as file name - timestamp in milliseconds is used for date representation.
/// This function converts file creation date into file name.
internal func fileNameFrom(fileCreationDate: Date) -> String {
    let millisecondsSinceReferenceDate = (fileCreationDate.timeIntervalSinceReferenceDate * 1_000).rounded().toUInt64() ?? 0
    return String(millisecondsSinceReferenceDate)
}

/// File creation date is used as file name - timestamp in milliseconds is used for date representation.
/// This function converts file name into file creation date.
internal func fileCreationDateFrom(fileName: String) -> Date {
    let millisecondsSinceReferenceDate = TimeInterval(UInt64(fileName) ?? 0) / 1_000
    return Date(timeIntervalSinceReferenceDate: TimeInterval(millisecondsSinceReferenceDate))
}

/// Extension for safe conversion (with no overflow) from `TimeInterval` to `UInt64`.
private extension TimeInterval {
    func toUInt64() -> UInt64? {
        return self >= TimeInterval(UInt64.min) && self < TimeInterval(UInt64.max) ? UInt64(self) : nil
    }
}
