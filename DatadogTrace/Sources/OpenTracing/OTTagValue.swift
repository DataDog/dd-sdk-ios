/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

/// Values of `OTSpan`tags.
public typealias OTTagValue = Encodable & Sendable

internal extension Dictionary where Key == String, Value == OTTagValue {
    /// Flattens nested dictionary values into separate tags, joining keys with `.`.
    /// E.g. `["ctx": ["foo": "bar"]]` becomes `["ctx.foo": "bar"]`.
    var flattened: [String: OTTagValue] {
        var tags: [String: OTTagValue] = [:]
        for (key, value) in self {
            if let nested = value as? [String: OTTagValue] {
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
