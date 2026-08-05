import Foundation
import DatadogInternal

/// Represents information related to an event with a timespan
public protocol OTSpan: Sendable {
    /// The span context that refers to this span
    var context: OTSpanContext { get }

    /// The tracer that produced this span
    func tracer() -> OTTracer

    /// Set the name of the operation this span represents
    ///
    /// - parameter operationName: The name of the operation this span represents
    func setOperationName(_ operationName: String)

    /// Add a new tag or replace an existing tag key with this value. If `value` is a `Dictionary`, it's flattened
    /// into one tag per leaf field (`"\(key).\(nestedKey)"`), recursively — see `setTag(key:value: [String:
    /// OTTagValue])` for dictionaries whose values mix concrete types. Structs and arrays are not flattened. See
    /// RUM-3357 for further discussion of these limitations.
    ///
    /// - parameter key:   Key of the tag to set
    /// - parameter value: Value of the tag to set
    func setTag(key: String, value: OTTagValue)

    /// Add a new tag or replace an existing tag key with this dictionary of values, flattening it the same way as
    /// `setTag(key:value: OTTagValue)` — this overload exists only so that dictionaries mixing concrete value
    /// types (e.g. `String` and `Int` in the same literal) compile at all; `setTag(key:value: OTTagValue)` alone
    /// can't infer a single concrete type for such a literal.
    ///
    /// Has a default implementation below — see it for why this is a requirement rather than a plain extension
    /// method, and when a conformer should override it. Note that Swift picks this overload over
    /// `setTag(key:value: OTTagValue)` only for dictionaries whose values mix concrete types — a homogeneous
    /// dictionary literal (e.g. all-`String` values) resolves to the scalar overload instead, even though both
    /// overloads flatten identically. A conformer with custom (non-flattening) behavior in its scalar `setTag`
    /// that relies on this default for the dictionary overload will flatten mixed-type dictionaries but not
    /// homogeneous ones — override both together if that inconsistency matters for your use case.
    ///
    /// - parameter key:   Key of the tag to set
    /// - parameter value: Dictionary of values to set, keyed by their nested tag name
    func setTag(key: String, value: [String: OTTagValue])

    /// Add a new log with the supplied fields and timestamp
    ///
    /// - parameter fields:    Fields to set on the span log
    /// - parameter timestamp: Timestamp to use for the span log
    func log(fields: [String: Encodable & Sendable], timestamp: Date)

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
    ///     let span2 = tracer.startSpan(operationName: "child of `span1`").setActive()
    ///
    ///     // As `span3` is a root span, it won't become the child of the active span:
    ///     let span3 = tracer.startRootSpan(operationName: "another root").setActive()
    ///
    @discardableResult
    func setActive() -> OTSpan
}

/// Convenience extension
public extension OTSpan {
    /// Add a new log with the supplied fields and the current timestamp
    ///
    /// - parameter fields: Fields to set on the span log
    func log(fields: [String: Encodable & Sendable]) {
        self.log(fields: fields, timestamp: Date())
    }

    /// Finish the span at the current time
    func finish() {
        self.finish(at: Date())
    }

    /// Default implementation of `setTag(key:value: [String: OTTagValue])`: flattens `value` fully — recursing
    /// into any nested dictionary itself, rather than relying on the conformer's own `setTag(key:value:
    /// OTTagValue)` to detect and recurse into one — then forwards each resulting leaf pair to
    /// `setTag(key:value: OTTagValue)` once. Conformers whose tag-setting has extra invariants beyond "store this
    /// key/value" (e.g. side effects triggered by specific keys, or a requirement to warn/log at most once per
    /// call regardless of how many leaves a dictionary flattens into) should override this with their own
    /// single-pass implementation instead of relying on this default, since it calls back into the public
    /// `setTag(key:value: OTTagValue)` once per leaf.
    func setTag(key: String, value: [String: OTTagValue]) {
        for (leafKey, leafValue) in flattenedTagPairs(key: key, dict: value) {
            setTag(key: leafKey, value: leafValue)
        }
    }
}

/// Error conveniences
public extension OTSpan {
    /// Set or replace the error for the given span.
    /// This is a convenience to set the proper tags with error details. Consider the `setError(message:stacktrace:file:line:)` variant for a better control over the error details.
    ///
    /// Using this API requires to enable logging on `Datadog.Configuration` using its builder:
    ///
    ///       builder
    ///         // ...
    ///         .enableLogging(true)
    ///         // ...
    ///         .build()
    ///
    /// - parameter error: An object conforming to the `Error` protocol.
    /// - parameter file: A string identifying the file where the `Error` was caught. The default is `#fileID` which means `ModuleName/Filename.extension`, consider an helpful yet concise identifier when overriding the default. Note that an empty string means skipping the `file` and `line` parameters.
    /// - parameter line: The line number in the file where the `Error` was caught.
    func setError(
        _ error: Error,
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        let dderror = DDError(error: error)
        setError(
            kind: dderror.type,
            message: dderror.message,
            stack: dderror.stack,
            file: file,
            line: line
        )
    }

    /// Set or replace the error for the given span.
    /// This is a convenience to set the proper tags with error details.
    ///
    ///  Using this API requires to enable logging on `Datadog.Configuration` using its builder:
    ///
    ///       builder
    ///         // ...
    ///         .enableLogging(true)
    ///         // ...
    ///         .build()
    ///
    /// - parameter kind: The type of error to be logged.
    /// - parameter message: An error message to be logged.
    /// - parameter stack: A string detailing the state of the stack when the error was caught. Note that it can also be any details that could help further triaging and investigation of the error downstream, it doesn't have to be an actual stack trace. Also note that an empty string means skipping the `stack` parameter.
    /// - parameter file: A string identifying the file where the error was caught. The default is `#fileID` which means `ModuleName/Filename.extension`, consider an helpful yet concise identifier when overriding the default. Note that an empty string means skipping the `file` and `line` parameters.
    /// - parameter line: The line number in the file where the error was caught.
    func setError(
        kind: String,
        message: String,
        stack: String = "",
        file: StaticString = #fileID,
        line: UInt = #line
    ) {
        var fields = [
            OTLogFields.event: "error",
            OTLogFields.errorKind: kind,
            OTLogFields.message: message
        ]
        var fileAndStack = [String]()
        if file.utf8CodeUnitCount > 0 {
            fileAndStack.append("\(file):\(line)")
        }
        if stack.count > 0 {
            fileAndStack.append(stack)
        }
        if fileAndStack.count > 0 {
            fields[OTLogFields.stack] = fileAndStack.joined(separator: "\n")
        }
        log(fields: fields)
    }
}

/// Sampling conveniences
public extension OTSpan {
    /// Forces the trace this span is part of to be kept, regardless of the sampling configuration.
    ///
    /// This API should be called on a root span immediately after its creation. Although calling it
    /// on any span will automatically keep all the spans of that trace (including parent, children,
    /// siblings, etc), if the trace was determined to be not sampled by the current sampling configuration,
    /// any span that has finished before this API is called will not be sampled, resulting in potentially
    /// incomplete traces.
    ///
    /// Calling this API immediately after creating the root span also guarantees that any propagation
    /// as part of distributed tracing includes the correct information regarding this trace sampling
    /// priority.
    ///
    /// - Note: This API is equivalent to calling `setTag(key: SpanTags.manualKeep, value: true)`.
    func keepTrace() {
        setTag(key: SpanTags.manualKeep, value: true)
    }

    /// Forces the trace this span is part of to be dropped, regardless of the sampling configuration.
    ///
    /// This API should be called on a root span immediately after its creation. Although calling it
    /// on any span will automatically drop all the spans of that trace (including parent, children,
    /// siblings, etc), if the trace was determined to be sampled by the current sampling configuration,
    /// any span that has finished before this API is called will be sampled, resulting in potentially
    /// incomplete traces.
    ///
    /// Calling this API immediately after creating the root span also guarantees that any propagation
    /// as part of distributed tracing includes the correct information regarding this trace sampling
    /// priority.
    ///
    /// - Note: This API is equivalent to calling `setTag(key: SpanTags.manualDrop, value: true)`.
    func dropTrace() {
        setTag(key: SpanTags.manualDrop, value: true)
    }
}
