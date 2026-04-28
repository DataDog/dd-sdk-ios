import Foundation

/// A single timestamped performance sample.
public struct Sample {
    /// Timestamp in nanoseconds.
    public let timestamp: Int64
    /// Metric value (e.g. bytes for memory, percent for CPU).
    public let value: Double

    public init(timestamp: Int64, value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}
