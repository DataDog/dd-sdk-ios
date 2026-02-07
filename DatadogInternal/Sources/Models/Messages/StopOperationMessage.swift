public struct StopOperationMessage {
    /// Correlation context to include with the profile submission.
    ///
    /// This context contains identifiers and correlation IDs that are merged
    /// into the profile event as additional attributes, enabling data correlation
    /// across different telemetry streams.
    public let context: [String: Encodable]

    /// Creates a new profiler stop message.
    ///
    /// - Parameter context: Correlation context containing IDs for data correlation.
    ///                      Such as session IDs, view IDs, or other telemetry identifiers.
    public init(context: [String: Encodable]) {
        self.context = context
    }
}
