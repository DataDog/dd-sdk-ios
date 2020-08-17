import Foundation

/// Represents information related to an event with a timespan
public protocol OTSpan {
    /// The span context that refers to this span
    var context: OTSpanContext { get }

    /// The tracer that produced this span
    func tracer() -> OTTracer

    /// Set the name of the operation this span represents
    ///
    /// - parameter operationName: The name of the operation this span represents
    func setOperationName(_ operationName: String)

    /// Add a new tag or replace an existing tag key with this value
    ///
    /// - parameter key:   Key of the tag to set
    /// - parameter value: Value of the tag to set
    func setTag(key: String, value: Encodable)

    /// Add a new log with the supplied fields and timestamp
    ///
    /// - parameter fields:    Fields to set on the span log
    /// - parameter timestamp: Timestamp to use for the span log
    func log(fields: [String: Encodable], timestamp: Date)

    /// Add a new baggage item or replace an existing baggage item value for the given key
    ///
    /// - parameter key:   Key of the baggage item to set
    /// - parameter value: Value of the baggage item to set
    func setBaggageItem(key: String, value: String)

    /// Get the baggage item corresponding to the given key; nil if the baggage item does not exist
    ///
    /// - parameter key: Key of the baggage item to get
    func baggageItem(withKey key: String) -> String?

    /// Finish the span at the specified time, or at some default time if nil
    ///
    /// - parameter time: If non-nil, time at which to finish the span; default time is used if nil
    func finish(at time: Date)

    /// Sets this span as the active span in the current execution context.
    /// The active span becomes the parent of any other span created in the same execution context
    /// if the parent is not set explicitly. The span remains active until it finishes or another span is set as active.
    ///
    /// Example:
    ///
    ///     // `span1` becomes active in this thread:
    ///     let span1 = tracer.startSpan(operationName: "root").setActive()
    ///
    ///     // As `span2` has no explicit parent, it becomes the child of the active `span1`:
    ///     let span2 = tracer.startSpan(operationName: "child of `span1`")
    ///
    ///     // As `span3` has the explicit parent (nil) it won't become the child of the active span:
    ///     let span3 = tracer.startSpan(operationName: "another root", childOf: nil)
    ///
    @discardableResult
    func setActive() -> OTSpan
}

/// Convenience extension
public extension OTSpan {
    /// Add a new log with the supplied fields and the current timestamp
    ///
    /// - parameter fields: Fields to set on the span log
    func log(fields: [String: Encodable]) {
        self.log(fields: fields, timestamp: Date())
    }

    /// Finish the span at the current time
    func finish() {
        self.finish(at: Date())
    }
}
