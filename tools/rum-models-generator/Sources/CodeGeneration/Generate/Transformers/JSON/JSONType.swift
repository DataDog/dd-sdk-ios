/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

/// Type-safe JSON schema.
internal protocol JSONType {}

internal enum JSONPrimitive: String, JSONType {
    case bool
    case double
    case integer
    case string
    /// A `bool`, `double`, `integer` or `string`
    case any
}

internal struct JSONArray: JSONType {
    let element: JSONType
}

internal struct JSONEnumeration: JSONType {
    enum Value {
        case string(value: String)
        case integer(value: Int)
    }

    let name: String
    let comment: String?
    let values: [Value]
}

internal struct JSONObject: JSONType {
    struct Property: JSONType {
        enum DefaultValue {
            case integer(value: Int)
            case string(value: String)
        }

        let name: String
        let comment: String?
        let type: JSONType
        let defaultValue: DefaultValue?
        let isRequired: Bool
        let isReadOnly: Bool
    }

    struct AdditionalProperties: JSONType {
        let comment: String?
        let type: JSONPrimitive
        let isReadOnly: Bool
    }

    let name: String
    let comment: String?
    let properties: [Property]
    let additionalProperties: AdditionalProperties?

    init(name: String, comment: String?, properties: [Property], additionalProperties: AdditionalProperties? = nil) {
        self.name = name
        self.comment = comment
        self.properties = properties.sorted { property1, property2 in property1.name < property2.name }
        self.additionalProperties = additionalProperties
    }
}

/// Represents non-homogeneous type which can be read from `oneOf` or `anyOf` JSON schema.
///
/// Ref.:
/// - https://json-schema.org/draft/2019-09/json-schema-core.html#rfc.section.9.2.1.2
/// - https://json-schema.org/draft/2019-09/json-schema-core.html#rfc.section.9.2.1.3
///
/// An example can be schema defining `oneOf` with an array of possible subschemas, where each
/// describes a different `JSONObject`.
internal struct JSONUnionType: JSONType {
    /// A type that this `JSONUnionType` can represent.
    struct ElementType {
        let name: String?
        let type: JSONType
    }

    let name: String
    let comment: String?
    /// An array of possible types that this `JSONUnionType` represents.
    let types: [ElementType]
}

// MARK: - Equatable

extension JSONObject: Equatable {
    static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}

extension JSONUnionType: Equatable {
    static func == (lhs: JSONUnionType, rhs: JSONUnionType) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}
