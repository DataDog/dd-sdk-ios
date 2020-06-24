import Foundation

/// "Format", "Carrier", "Extract", "Inject", and "Text Map" are opentracing-specific concepts. See:
/// https://github.com/opentracing/specification/blob/master/specification.md#inject-a-spancontext-into-a-carrier
/// https://github.com/opentracing/specification/blob/master/specification.md#extract-a-spancontext-from-a-carrier
/// https://github.com/opentracing/specification/blob/master/specification.md#note-required-formats-for-injection-and-extraction

/// Format and carrier for extract().
/// A FormatReader is used to extract a SpanContext from a carrier.
/// The type of the child protocol is the format descriptor.
/// The carrier is specified by the protocol's return type for the getter, usually `getAll()`.
///
/// Marker protocol.
public protocol OTFormatReader: OTCustomFormatReader {}

/// Format and carrier for inject().
/// A FormatWriter is used to inject a SpanContext into a carrier.
/// The type of the child protocol is the format descriptor.
/// The carrier is specified by the protocol's parameter type for the setter, usually `setAll()`
///
/// Marker protocol.
public protocol OTFormatWriter: OTCustomFormatWriter {}

/// Read interface for a textmap
public protocol OTTextMapReader: OTFormatReader {}

/// Write interface for a textmap
public protocol OTTextMapWriter: OTFormatWriter {}

/// Read interface for HTTP headers
public protocol OTHTTPHeadersReader: OTTextMapReader {}

/// Write interface for HTTP headers
public protocol OTHTTPHeadersWriter: OTTextMapWriter {}

/// Read interface for a custom carrier
public protocol OTCustomFormatReader {
    /// Extract a span context from the custom carrier
    ///
    /// - returns: extracted span context from the custom carrier, or nil on failure
    func extract() -> OTSpanContext?
}

/// Write interface for a custom carrier
public protocol OTCustomFormatWriter {
    /// Inject a span context into the custom carrier
    ///
    /// - parameter spanContext: context to inject into the custom carrier
    func inject(spanContext: OTSpanContext)
}
