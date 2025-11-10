import Foundation
import DatadogInternal

/// Tracer is the starting point for all OpenTracing instrumentation. Use it
/// to create OTSpans, inject/extract them between processes, and so on.
/// 
/// Tracer should be thread-safe.
public protocol OTTracer {
    /// Start a new span with the given operation name.
    ///
    /// - parameter operationName: the operation name for the newly-started span
    /// - parameter references:    an optional list of Reference instances to record causal relationships. If no
    ///                            reference is provided, and an active span exists in the current execution context
    ///                            the active span will be used as the parent.
    /// - parameter tags:          a set of tag keys and values per `OTSpan#setTag:value:`, or `nil` to start with
    ///                            an empty tag map
    /// - parameter startTime:     an explicitly specified start timestamp for the `OTSpan`, or `nil` to use the
    ///                            current walltime
    /// - returns:                 a valid Span instance; it is the caller's responsibility to call `finish()`.
    func startSpan(
        operationName: String,
        references: [OTReference]?,
        tags: [String: Encodable]?,
        startTime: Date?
    ) -> OTSpan

    /// Start a new root span with the given operation name.
    /// - Parameters:
    ///   - operationName:    the operation name for the newly-started span
    ///   - tags:             a set of tag keys and values per `OTSpan#setTag:value:`, or `nil` to start with
    ///                       an empty tag map
    ///   - startTime:        an explicitly specified start timestamp for the `OTSpan`, or `nil` to use the
    ///                       current walltime
    ///   - customSampleRate: a sample rate that overrides the general Tracing configuration’s sample rate.
    /// - returns:            a valid Span instance; it is the caller's responsibility to call `finish()`.
    func startRootSpan(
        operationName: String,
        tags: [String: Encodable]?,
        startTime: Date?,
        customSampleRate: SampleRate?
    ) -> OTSpan

    /// Transfer the span information into the carrier of the given format.
    ///
    /// For example:
    ///
    ///     let httpHeaders: [String: String] = ...
    ///     OpenTracing.Tracer.shared().inject(spanContext: span, format: OpenTracing.Format.TextMap,
    ///                                        carrier: httpHeaders)
    ///
    /// - SeeAlso: [propagation](http://opentracing.io/propagation/)
    ///
    /// - parameter spanContext: the OTSpanContext instance to inject
    /// - parameter writer:      the desired inject carrier format and corresponding carrier. Format is
    ///                          specified via the type, and the carrier is the backing store being written
    ///                          to.
    func inject(spanContext: OTSpanContext, writer: OTFormatWriter)

    /// Extract a SpanContext previously (and remotely) injected into the carrier of the given format.
    /// 
    /// For example:
    ///     let headerMap: [String: String] = req.headers // or similar
    ///     OpenTracing.SpanContext ctx =
    ///         OpenTracing.Tracer.shared().extract(format: OpenTracing.Format.TextMap, carrier: headerMap)
    ///     OpenTracing.Span span =
    ///         OpenTracing.Tracer.shared().startSpan(operationName: "methodName", childOf: ctx)
    ///
    /// - SeeAlso: [propagation](http://opentracing.io/propagation/)
    /// 
    /// - parameter reader:  the desired extract carrier format and corresponding carrier. Format is
    ///                      specified via the type, and the carrier is the backing store being read from.
    /// @returns a newly-created OTSpanContext that belongs to the trace previously
    ///        injected into the carrier (presumably in a remote process)
    /// 
    func extract(reader: OTFormatReader) -> OTSpanContext?

    /// Returns the active span in the current execution context, this span will be automatically assigned as the parent of any
    /// created Span without explicit parent.
    /// For a span to be set as the active one in the current context, it must explicitly call `span.setActive()`.
    /// This method can return different results depending on the context that is executed.
    var activeSpan: OTSpan? { get }
}

/// Extension for a convenience startSpan() with a single parent rather than a list of references
public extension OTTracer {
    /// Start a new span with the given operation name.
    ///
    /// - parameter operationName: the operation name for the newly-started span
    /// - parameter parent:        span context that will be a parent reference. If no
    ///                            reference is provided, and an active span exists in the current execution context
    ///                            the active span will be used as the parent.
    /// - parameter tags:          a set of tag keys and values per OTSpan#setTag:value:, or nil to start with
    ///                            an empty tag map
    /// - parameter startTime:     an explicitly specified start timestamp for the OTSpan, or nil to use the
    ///                            current walltime
    /// - returns:                 a valid Span instance; it is the caller's responsibility to call finish()
    func startSpan(
        operationName: String,
        childOf parent: OTSpanContext? = nil,
        tags: [String: Encodable]? = nil,
        startTime: Date? = nil
    ) -> OTSpan {
        let references = parent.map { [OTReference.child(of: $0)] }
        return self.startSpan(
            operationName: operationName,
            references: references,
            tags: tags,
            startTime: startTime
        )
    }

    /// Start a new root span with the given operation name.
    /// - Parameters:
    ///   - operationName:    the operation name for the newly-started span
    ///   - tags:             a set of tag keys and values per `OTSpan#setTag:value:`, or `nil` to start with
    ///                       an empty tag map
    ///   - startTime:        an explicitly specified start timestamp for the `OTSpan`, or `nil` to use the
    ///                       current walltime
    ///   - customSampleRate: a sample rate that overrides the general Tracing configuration’s sample rate.
    /// - returns:            a valid Span instance; it is the caller's responsibility to call `finish()`.
    func startRootSpan(
        operationName: String,
        tags: [String: Encodable]? = nil,
        startTime: Date? = nil,
        customSampleRate: SampleRate? = nil
    ) -> OTSpan {
        return self.startRootSpan(
            operationName: operationName,
            tags: tags,
            startTime: startTime,
            customSampleRate: customSampleRate
        )
    }
}
