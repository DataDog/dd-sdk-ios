/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public typealias SpanID = TraceID

public struct TraceID: RawRepresentable, Equatable, Hashable {
    /// The `String` representation format of a `TraceID`.
    public enum Representation {
        case decimal
        case hexadecimal
        case hexadecimal16Chars
        case hexadecimal32Chars
    }

    /// The unique integer (64-bit unsigned) ID of the trace containing this span.
    /// - See also: [Datadog API Reference - Send Traces](https://docs.datadoghq.com/api/?lang=bash#send-traces)
    public let rawValue: UInt64

    /// Creates a new instance with the specified raw value.
    ///
    /// - Parameter rawValue: The raw value to use for the new instance.
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
}

extension TraceID {
    /// Creates a `TraceID` from a `String` representation.
    ///
    /// - Parameters:
    ///   - string: The `String` representation.
    ///   - representation: The representation, `.decimal` by default.
    public init?(_ string: String, representation: Representation = .decimal) {
        switch representation {
        case .decimal:
            guard let rawValue = UInt64(string) else {
                return nil
            }

            self.init(rawValue: rawValue)
        case .hexadecimal, .hexadecimal16Chars, .hexadecimal32Chars:
            guard let rawValue = UInt64(string, radix: 16) else {
                return nil
            }

            self.init(rawValue: rawValue)
        }
    }
}

extension TraceID: ExpressibleByIntegerLiteral {
    /// Creates an instance initialized to the specified integer value.
    ///
    /// Do not call this initializer directly. Instead, initialize a variable or
    /// constant using an integer literal. For example:
    ///
    ///     let id: TraceID = 23
    ///
    /// In this example, the assignment to the `id` constant calls this integer
    /// literal initializer behind the scenes.
    ///
    /// - Parameter value: The value to create.
    public init(integerLiteral value: UInt64) {
        self.init(rawValue: value)
    }
}

extension String {
    /// Creates a `String` representation of a `TraceID`.
    ///
    /// - Parameters:
    ///   - traceID: The Trace ID
    ///   - representation: The required representation. `.decimal` by default.
    public init(_ traceID: TraceID, representation: TraceID.Representation = .decimal) {
        switch representation {
        case .decimal:
            self.init(traceID.rawValue)
        case .hexadecimal:
            self.init(traceID.rawValue, radix: 16)
        case .hexadecimal16Chars:
            self.init(format: "%016llx", traceID.rawValue)
        case .hexadecimal32Chars:
            self.init(format: "%032llx", traceID.rawValue)
        }
    }
}

/// A `TraceID` generator interface.
public protocol TraceIDGenerator {
    /// Generates a new and unique `TraceID`.
    ///
    /// - Returns: The generated `TraceID`
    func generate() -> TraceID
}

/// A Default `TraceID` genarator.
public struct DefaultTraceIDGenerator: TraceIDGenerator {
    /// Describes the lower and upper boundary of tracing ID generation.
    ///
    /// * Lower: starts with `1` as `0` is reserved for historical reason: 0 == "unset", ref: dd-trace-java:DDId.java.
    /// * Upper: equals to `2 ^ 63 - 1` as some tracers can't handle the `2 ^ 64 -1` range, ref: dd-trace-java:DDId.java.
    public static let defaultGenerationRange = (1...UInt64.max >> 1)

    /// The generator's range.
    let range: ClosedRange<UInt64>

    /// Creates a default generator.
    /// 
    /// - Parameter range: The generator's range.
    public init(range: ClosedRange<UInt64> = Self.defaultGenerationRange) {
        self.range = range
    }

    /// Generates a new and unique `TraceID`.
    ///
    /// The Trace ID will be generated within the range.
    ///
    /// - Returns: The generated `TraceID`
    public func generate() -> TraceID {
        return TraceID(rawValue: .random(in: range))
   }
}
