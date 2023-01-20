/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

/// Type-safe Swift schema.
public protocol SwiftType {}

/// Swift primitive type.
public protocol SwiftPrimitiveType: SwiftType {}
/// An allowed value of Swift primitive type.
public protocol SwiftPrimitiveValue {}
/// An allowed default value of Swift property.
public protocol SwiftPropertyDefaultValue {}
/// An allowed value of Swift with no obj-c interoperability.
public protocol SwiftPrimitiveNoObjcInteropType: SwiftPrimitiveType {}

extension Bool: SwiftPrimitiveValue, SwiftPropertyDefaultValue {}
extension Int: SwiftPrimitiveValue, SwiftPropertyDefaultValue {}
extension Int64: SwiftPrimitiveValue, SwiftPropertyDefaultValue {}
extension String: SwiftPrimitiveValue, SwiftPropertyDefaultValue {}
extension Double: SwiftPrimitiveValue, SwiftPropertyDefaultValue {}

/// Represents `Swift.Codable` - we need to define utility type because it cannot be declared as `extension` to `Codable`.
public struct SwiftCodable: SwiftPrimitiveNoObjcInteropType {}

/// Represents `Swift.Encodable` - we need to define utility type because it cannot be declared as `extension` to `Encodable`.
public struct SwiftEncodable: SwiftPrimitiveNoObjcInteropType {}

public struct SwiftPrimitive<T: SwiftPrimitiveValue>: SwiftPrimitiveType {
    public init() {}
}

public struct SwiftArray: SwiftType {
    public var element: SwiftType
}

public struct SwiftDictionary: SwiftType {
    public let key = SwiftPrimitive<String>()
    public var value: SwiftPrimitiveType
}

/// An `enum` with raw-type cases.
public struct SwiftEnum: SwiftType {
    public struct Case: SwiftType, SwiftPropertyDefaultValue {
        public enum RawValue {
            case string(value: String)
            case integer(value: Int)
        }
        public var label: String
        public var rawValue: RawValue
    }

    public var name: String
    public var comment: String?
    public var cases: [Case]
    public var conformance: [SwiftProtocol]
}

/// An `enum` with associated-type cases.
public struct SwiftAssociatedTypeEnum: SwiftType {
    public struct Case: SwiftType, SwiftPropertyDefaultValue {
        public var label: String
        public var associatedType: SwiftType
    }

    public var name: String
    public var comment: String?
    public var cases: [Case]
    public var conformance: [SwiftProtocol]
}

public struct SwiftStruct: SwiftType {
    public struct Property: SwiftType {
        /// Mutability levels of a property.
        /// From the lowest `immutable` to the highest `mutable`.
        public enum Mutability: Int {
            case immutable
            case mutableInternally
            case mutable
        }

        public enum CodingKey {
            /// Static coding key with fixed value.
            case `static`(value: String)
            /// Dynamic coding key with value determined at runtime.
            case `dynamic`

            public var isStatic: Bool {
                switch self {
                case .static: return true
                case .dynamic: return false
                }
            }
        }

        public var name: String
        public var comment: String?
        public var type: SwiftType
        public var isOptional: Bool
        public var mutability: Mutability
        public var defaultValue: SwiftPropertyDefaultValue?
        public var codingKey: CodingKey
    }

    public var name: String
    public var comment: String?
    public var properties: [Property]
    public var conformance: [SwiftProtocol]
}

public struct SwiftProtocol: SwiftType {
    public var name: String
    public var conformance: [SwiftProtocol]

    public init(name: String, conformance: [SwiftProtocol]) {
        self.name = name
        self.conformance = conformance
    }
}

/// Reference to any other Swift type.
public struct SwiftTypeReference: SwiftType {
    public var referencedTypeName: String

    public init(referencedTypeName: String) {
        self.referencedTypeName = referencedTypeName
    }
}

public let codableProtocol = SwiftProtocol(name: "Codable", conformance: [])

// MARK: - Helpers

public extension SwiftType {
    /// The name of this type (or `nil` if this type is unnamed).
    var typeName: String? {
        let `struct` = self as? SwiftStruct
        let `enum` = self as? SwiftEnum
        let associatedTypeEnum = self as? SwiftAssociatedTypeEnum
        return `struct`?.name ?? `enum`?.name ?? associatedTypeEnum?.name
    }
}

// MARK: - Equatable

extension SwiftStruct: Equatable {
    public static func == (lhs: SwiftStruct, rhs: SwiftStruct) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}

extension SwiftEnum: Equatable {
    public static func == (lhs: SwiftEnum, rhs: SwiftEnum) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}

public func == (lhs: SwiftType, rhs: SwiftType) -> Bool {
    return String(describing: lhs) == String(describing: rhs)
}

public func != (lhs: SwiftType, rhs: SwiftType) -> Bool {
    return !(lhs == rhs)
}
