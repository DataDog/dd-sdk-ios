import Foundation

/// A single timestamped performance sample.
struct Sample {
    /// Timestamp in nanoseconds.
    let timestamp: Int64
    /// Metric value (e.g. bytes for memory, percent for CPU).
    let value: Double
}
