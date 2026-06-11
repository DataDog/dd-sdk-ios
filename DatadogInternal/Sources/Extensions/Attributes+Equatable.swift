/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

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
}

/// Recursively compares two values for equality.
///
/// Accepts `Any` (not `Encodable`) so Swift can open the existential for `AnyHashable` casting.
/// - `[Any]` arrays and `[String: Any]` objects are compared element-wise (the storage
///   format produced by `AnyDecodable` when decoding JSON arrays and objects).
/// - All `Hashable` types — scalars, typed arrays (`[String]`, `[Int]`, …) — are compared
///   via `AnyHashable`. Non-`Hashable`, non-collection values are treated as unequal.
private func isAnyEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    // Unwrap AnyCodable to reach the underlying Any value
    if let l = lhs as? AnyCodable, let r = rhs as? AnyCodable {
        return isAnyEqual(l.value, r.value)
    }

    if let l = lhs as? [Any], let r = rhs as? [Any] {
        guard l.count == r.count else {
            return false
        }

        return zip(l, r).allSatisfy { isAnyEqual($0, $1) }
    }

    if let l = lhs as? [String: Any], let r = rhs as? [String: Any] {
        guard l.count == r.count else {
            return false
        }

        return l.allSatisfy { key, lVal in r[key].map { isAnyEqual(lVal, $0) } ?? false }
    }

    guard let l = lhs as? AnyHashable, let r = rhs as? AnyHashable else {
        return false
    }

    return l == r
}
