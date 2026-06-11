/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Equatable conformance for `DatadogExtension` wrapping `[String: Encodable]`.
///
/// Used by generated RUM model `==` implementations to compare dynamic attribute
/// dictionaries whose value type (`Encodable`) has no built-in equality.
extension DatadogExtension: Equatable where ExtendedType == [String: Encodable] {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        guard lhs.type.count == rhs.type.count else {
            return false
        }

        return lhs.type.allSatisfy { key, lhsVal in
            guard let rhsVal = rhs.type[key] else {
                return false
            }

            return isAnyEqual(lhsVal, rhsVal)
        }
    }

    /// Recursively compares two values for equality.
    ///
    /// Accepts `Any` (not `Encodable`) so Swift can open the existential for `AnyHashable` casting.
    /// - `[Any]` arrays and `[String: Any]` objects are compared element-wise (the storage
    ///   format produced by `AnyDecodable` when decoding JSON arrays and objects).
    /// - All `Hashable` types — scalars, typed arrays (`[String]`, `[Int]`, …) — are compared
    ///   via `AnyHashable`. Non-`Hashable`, non-collection values are treated as unequal.
    private static func isAnyEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        switch (lhs, rhs) {
        // Unwrap AnyCodable independently on either side so a raw value and a decoded
        // wrapper for the same content compare equal (e.g. after a JSON round-trip).
        case (let l as AnyCodable, _): return isAnyEqual(l.value, rhs)
        case (_, let r as AnyCodable): return isAnyEqual(lhs, r.value)
        // Unwrap AnyEncodable (used by the ObjC bridge via `swiftAttributes`).
        case (let l as AnyEncodable, _): return isAnyEqual(l.value, rhs)
        case (_, let r as AnyEncodable): return isAnyEqual(lhs, r.value)
        case (let l as [Any], let r as [Any]) where l.count == r.count:
            return zip(l, r).allSatisfy { isAnyEqual($0, $1) }
        case (let l as [String: Any], let r as [String: Any]) where l.count == r.count:
            return l.allSatisfy { key, lVal in r[key].map { isAnyEqual(lVal, $0) } ?? false }
        // Normalize URL to its absoluteString so it compares equal to the String
        // produced by AnyEncodable's encode path after a JSON round-trip.
        case (let l as URL, _): return isAnyEqual(l.absoluteString, rhs)
        case (_, let r as URL): return isAnyEqual(lhs, r.absoluteString)
        case (let l as AnyHashable, let r as AnyHashable): return l == r
        default:
            return false
        }
    }
}
