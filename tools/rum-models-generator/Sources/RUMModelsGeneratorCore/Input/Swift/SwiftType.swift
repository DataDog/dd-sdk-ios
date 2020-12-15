/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Type-safe Swift schema.
internal protocol SwiftType {}

/// Swift primitive type.
internal protocol SwiftPrimitiveType: SwiftType {}
/// An allowed value of Swift primitive type.
internal protocol SwiftPrimitiveValue {}
/// An allowed default value of Swift property.
internal protocol SwiftPropertyDefaultValue {}

extension Bool: SwiftPrimitiveValue, SwiftPropertyDefaultValue {}
extension Int: SwiftPrimitiveValue, SwiftPropertyDefaultValue {}
extension Int64: SwiftPrimitiveValue, SwiftPropertyDefaultValue {}
extension String: SwiftPrimitiveValue, SwiftPropertyDefaultValue {}
extension Double: SwiftPrimitiveValue, SwiftPropertyDefaultValue {}

internal struct SwiftPrimitive<T: SwiftPrimitiveValue>: SwiftPrimitiveType {}

internal struct SwiftArray: SwiftType {
    var element: SwiftType
}

internal struct SwiftEnum: SwiftType {
    struct Case: SwiftType, SwiftPropertyDefaultValue {
        var label: String
        var rawValue: String
    }

    var name: String
    var comment: String?
    var cases: [Case]
    var conformance: [SwiftProtocol]
}

internal struct SwiftStruct: SwiftType {
    struct Property: SwiftType {
        var name: String
        var comment: String?
        var type: SwiftType
        var isOptional: Bool
        var isMutable: Bool
        var defaultVaule: SwiftPropertyDefaultValue?
        var codingKey: String
    }

    var name: String
    var comment: String?
    var properties: [Property]
    var conformance: [SwiftProtocol]
}

internal struct SwiftProtocol: SwiftType {
    var name: String
    var conformance: [SwiftProtocol]
}

internal let codableProtocol = SwiftProtocol(name: "Codable", conformance: [])

// MARK: - Equatable

extension SwiftStruct: Equatable {
    static func == (lhs: SwiftStruct, rhs: SwiftStruct) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}
