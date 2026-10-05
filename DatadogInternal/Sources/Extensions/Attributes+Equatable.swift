/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

/// Equatable conformance for `DatadogExtension` wrapping `[String: Encodable]`.
///
/// Used by generated RUM model `==` implementations to compare dynamic attribute
/// dictionaries whose value type (`Encodable`) has no built-in equality. This drives
/// view-event diffing: two events whose attribute dictionaries compare equal produce
/// no delta for the `context` field.
///
/// ## Comparison strategy
///
/// Values are compared recursively via `isAnyEqual(_:_:)`:
/// - `AnyCodable` / `AnyEncodable` wrappers are unwrapped before comparison so that
///   a raw Swift value and its decoded or ObjC-bridged wrapper for the same content
///   compare equal.
/// - `[Any]` arrays and `[String: Any]` dictionaries are compared element-wise
///   (the in-memory format used by `AnyDecodable` for JSON collections).
/// - Any remaining `Hashable` scalar — `Bool`, `Int`, `String`, typed arrays, … — is
///   compared via `AnyHashable`.
///
/// ## Known limitations
///
/// - **Non-`Hashable` custom types**: a custom `Encodable` value that does not also
///   conform to `Hashable` falls through to the `default` branch and is always
///   considered unequal. Unchanged attributes of such a type will therefore always
///   appear as changed in a delta and trigger a redundant update event. This is an
///   inherent limitation of type-erased `Encodable` storage; a proper fix would
///   require JSON-encoding both sides for comparison, which is too costly for
///   in-memory diffing.
/// - **ObjC `NSNumber` vs Swift `Bool`**: `AnyEncodable` unwrapping handles the
///   common ObjC-bridge path, but a bare `NSNumber(value: true)` reaching the
///   `AnyHashable` branch compares unequal to a Swift `Bool`. This edge case only
///   arises when the same attribute key is written from both ObjC and Swift code;
///   it is a pre-existing cross-bridge limitation and is not specific to this PR.
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

    /// Recursively compares two values for equality. See the type-level documentation for the
    /// full comparison strategy and known limitations.
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
        case (let l as AnyHashable, let r as AnyHashable): return l == r
        default:
            return false
        }
    }
}
