/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public struct TraceID: RawRepresentable, Equatable, Hashable {
    /// The `String` representation format of a `TraceID`.
    public enum Representation {
        case decimal
        case hexadecimal
        case hexadecimal16Chars
        case hexadecimal32Chars
    }

    /// The unique 128-bit identifier for a trace.
    public var rawValue: (UInt64, UInt64) {
        get {
            return (idHi, idLo)
        }
    }

    /// Invalid trace ID with all bits set to `0`.
    public static let invalidId: UInt64 = 0

    /// Invalid trace ID.
    public static let invalid = TraceID()

    /// The unique integer (64-bit unsigned) ID of the trace
    /// (high 64 bits of the 128-bit trace ID).
    public private(set) var idHi: UInt64

    /// The unique integer (64-bit unsigned) ID of the trace
    /// (low 64 bits of the 128-bit trace ID).
    public private(set) var idLo: UInt64

    /// The `String` representation of high 64 bits of the trace ID.
    public var idHiHex: String {
        return String(format: "%llx", idHi)
    }

    /// The `String` representation of low 64 bits of the trace ID.
    public var idLoHex: String {
        return String(format: "%llx", idLo)
    }

    /// Creates a new instance with the specified raw value.
    /// - Parameter rawValue: Tuple of two `UInt64` values representing high and
    /// low 64 bits of the trace ID.
    public init(rawValue: (UInt64, UInt64)) {
        self.init(idHi: rawValue.0, idLo: rawValue.1)
    }

    /// Creates a new instance with the specified low 64 bits of the trace ID.
    /// - Parameter idLo: The low 64 bits of the trace ID.
    public init(idLo: UInt64) {
        self.init(rawValue: (0, idLo))
    }

    /// Creates a new instance with the specified high and low 64 bits of the trace ID.
    /// - Parameters:
    ///   - idHi: High 64 bits of the trace ID.
    ///   - idLo: Low 64 bits of the trace ID.
    public init(idHi: UInt64, idLo: UInt64) {
        self.idHi = idHi
        self.idLo = idLo
    }

    /// Creates a new instance with invalid trace ID.
    public init() {
        self.idHi = Self.invalidId
        self.idLo = Self.invalidId
    }

    /// Returns `String` representation of the trace ID.
    /// - Parameter representation: The required representation.
    /// - Returns: The `String` representation of the trace ID.
    public func toString(representation: Representation) -> String {
        String(self, representation: representation)
    }
}

extension TraceID: Codable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(toString(representation: .hexadecimal))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let traceID = TraceID(string, representation: .hexadecimal) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid TraceID")
        }
        self = traceID
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
            guard let idLo = UInt64(string) else {
                return nil
            }

            self.init(idLo: idLo)
        case .hexadecimal16Chars:
            guard let idLo = UInt64(string, radix: 16) else {
                return nil
            }

            self.init(idLo: idLo)
        case .hexadecimal32Chars:
            guard let idLo = UInt64(string, radix: 16), let idHi = UInt64(string.prefix(16), radix: 16) else {
                return nil
            }

            self.init(rawValue: (idHi, idLo))
        case .hexadecimal:
            if string.count > 16 && string.count <= 32 {
                let strLo = string[string.index(string.endIndex, offsetBy: -16)...]
                let strHi = string[string.startIndex..<string.index(string.endIndex, offsetBy: -16)]
                guard let idLo = UInt64(strLo, radix: 16), let idHi = UInt64(strHi, radix: 16) else {
                    return nil
                }

                self.init(rawValue: (idHi, idLo))
            } else if string.count <= 16 {
                guard let idLo = UInt64(string, radix: 16) else {
                    return nil
                }

                self.init(idLo: idLo)
            } else {
                return nil
            }
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
        self.init(rawValue: (0, value))
    }
}

extension String {
    /// Creates a `String` representation of a `TraceID`.
    /// Leading zeros are not included.
    /// - Parameters:
    ///   - traceID: The Trace ID
    ///   - representation: The required representation. `.decimal` by default.
    public init(_ traceID: TraceID, representation: TraceID.Representation) {
        switch representation {
        case .decimal:
            self.init(traceID.idLo)
        case .hexadecimal:
            if traceID.idHi == TraceID.invalidId {
                self.init(format: "%llx", traceID.idLo)
            } else {
                self.init(format: "%llx%016llx", traceID.idHi, traceID.idLo)
            }
        case .hexadecimal16Chars:
            self.init(format: "%016llx", traceID.idLo)
        case .hexadecimal32Chars:
            self.init(format: "%016llx%016llx", traceID.idHi, traceID.idLo)
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
        var idHi: UInt64
        var idLo: UInt64
        repeat {
            idHi = UInt64.random(in: range)
            idLo = UInt64.random(in: range)
        } while idHi == TraceID.invalidId && idLo == TraceID.invalidId
        return TraceID(idHi: idHi, idLo: idLo)
   }
}
