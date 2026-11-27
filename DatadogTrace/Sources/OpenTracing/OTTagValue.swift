/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
@preconcurrency import DatadogInternal

/// Values of `OTSpan`tags.
public typealias OTTagValue = Encodable & Sendable

/// Converts an untyped value, e.g. from the Objective-C bridge, into a tag value: strings and URLs are kept as they are,
/// so they are sent without JSON encoding, and anything else is wrapped in `AnyEncodable`.
internal func castTagValueToSwift(_ value: Any) -> OTTagValue {
    switch value {
    case let string as String: return string
    case let url as URL: return url
    default: return AnyEncodable(value)
    }
}

/// Returns `value` as a dictionary of tags if it is one: either a Swift `[String: OTTagValue]`, or a `[String: Any]`
/// wrapped in `AnyEncodable`, as dictionaries coming from the Objective-C bridge are.
internal func tagDictionary(from value: OTTagValue) -> [String: OTTagValue]? {
    if let dictionary = value as? [String: OTTagValue] {
        return dictionary
    }
    if let dictionary = (value as? AnyEncodable)?.value as? [String: Any] {
        return dictionary.mapValues(castTagValueToSwift)
    }
    return nil
}

internal extension Dictionary where Key == String, Value == OTTagValue {
    /// Flattens nested dictionary values into separate tags, joining keys with `.`.
    /// E.g. `["ctx": ["foo": "bar"]]` becomes `["ctx.foo": "bar"]`.
    /// Keys are sorted, so on collision a literal dotted key (`"ctx.foo"`) always wins over a nested one.
    var flattened: [String: OTTagValue] {
        var tags: [String: OTTagValue] = [:]
        for (key, value) in self.sorted(by: { $0.key < $1.key }) {
            if let nested = tagDictionary(from: value) {
                for (nestedKey, nestedValue) in nested.flattened {
                    tags["\(key).\(nestedKey)"] = nestedValue
                }
            } else {
                tags[key] = value
            }
        }
        return tags
    }
}
