/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import Datadog

/// Casts `[String: Any]` attributes to their `Encodable` representation by wrapping each `Any` into `AnyEncodable`.
internal func castAttributesToSwift(_ attributes: [String: Any]) -> [String: Encodable] {
    return attributes.mapValues { DDAnyEncodable($0) }
}

/// Casts `[String: Encodable]` attributes to their `Any` representation by unwrapping each `AnyEncodable` into `Any`.
internal func castAttributesToObjectiveC(_ attributes: [String: Encodable]) -> [String: Any] {
    return attributes
        .compactMapValues { value in (value as? DDAnyEncodable)?.value }
}

/// Helper extension to use `castAttributesToObjectiveC(_:)` in auto generated ObjC interop `RUMDataModels`.
/// Unlike the function it wraps, it has postfix notation which makes it easier to use in generated code.
internal extension Dictionary where Key == String, Value == Encodable {
    func castToObjectiveC() -> [String: Any] {
        return castAttributesToObjectiveC(self)
    }
}
