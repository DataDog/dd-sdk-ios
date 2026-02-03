/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public struct SpanID: RawRepresentable, Equatable, Hashable, Sendable {
    public static let invalidId: UInt64 = 0
    public static let invalid = SpanID()

    /// The `String` representation format of a `SpanID`.
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

    public init() {
        self.rawValue = Self.invalidId
    }

    public func toString(representation: Representation) -> String {
        String(self, representation: representation)
    }
}

extension SpanID {
    /// Creates a `SpanID` from a `String` representation.
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

extension SpanID: ExpressibleByIntegerLiteral {
    /// Creates an instance initialized to the specified integer value.
    ///
    /// Do not call this initializer directly. Instead, initialize a variable or
    /// constant using an integer literal. For example:
    ///
    ///     let id: SpanID = 23
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
    /// Creates a `String` representation of a `SpanID`.
    ///
    /// - Parameters:
    ///   - spanID: The Trace ID
    ///   - representation: The required representation. `.decimal` by default.
    public init(_ spanID: SpanID, representation: SpanID.Representation = .decimal) {
        switch representation {
        case .decimal:
            self.init(spanID.rawValue)
        case .hexadecimal:
            self.init(spanID.rawValue, radix: 16)
        case .hexadecimal16Chars:
            self.init(format: "%016llx", spanID.rawValue)
        case .hexadecimal32Chars:
            self.init(format: "%032llx", spanID.rawValue)
        }
    }
}

/// A `SpanID` generator interface.
public protocol SpanIDGenerator: Sendable {
    /// Generates a new and unique `SpanID`.
    ///
    /// - Returns: The generated `SpanID`
    func generate() -> SpanID
}

/// A Default `SpanID` genarator.
public struct DefaultSpanIDGenerator: SpanIDGenerator {
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

    /// Generates a new and unique `SpanID`.
    ///
    /// The Trace ID will be generated within the range.
    ///
    /// - Returns: The generated `SpanID`
    public func generate() -> SpanID {
        var rawValue: UInt64
        repeat {
            rawValue = UInt64.random(in: range)
        } while rawValue == SpanID.invalidId
        return SpanID(rawValue: rawValue)
   }
}

extension SpanID: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        do {
            let rawValue = try container.decode(UInt64.self)
            self.init(rawValue: rawValue)
        } catch {
            let rawValue = try container.decode(String.self)
            guard let spanID = SpanID(rawValue, representation: .decimal) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid SpanID format: \(rawValue)")
            }
            self = spanID
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
