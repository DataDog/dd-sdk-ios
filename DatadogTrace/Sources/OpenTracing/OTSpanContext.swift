/// Span context captures any implementation-dependent state such as trace ID and span ID, as well as the
/// baggage items
public protocol OTSpanContext {
    /// Iterate through the baggage items
    ///
    /// - parameter callback: Lambda invoked with each baggage item key-value pair as the parameters.
    ///                       If the lambda returns true, iteration will stop.
    func forEachBaggageItem(callback: (_ key: String, _ value: String) -> Bool)
}
