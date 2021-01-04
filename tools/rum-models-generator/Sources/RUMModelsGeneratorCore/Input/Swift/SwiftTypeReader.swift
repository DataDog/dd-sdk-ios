/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Reads `SwiftStruct` definition from `JSONObject`.
internal class SwiftTypeReader {
    func readSwiftStruct(from object: JSONObject) throws -> SwiftStruct {
        return try readStruct(from: object)
    }

    // MARK: - Reading ambiguous types

    private func readAnyType(from type: JSONType) throws -> SwiftType {
        switch type {
        case let primitive as JSONPrimitive:
            return readPrimitive(from: primitive)
        case let array as JSONArray:
            return try readArray(from: array)
        case let enumeration as JSONEnumeration:
            return readEnum(from: enumeration)
        case let object as JSONObject:
            return try readSwiftStruct(from: object)
        default:
            throw Exception.unimplemented("Transform \(type) into `SwiftType` is not supported.")
        }
    }

    // MARK: - Reading concrete types

    private func readPrimitive(from primitive: JSONPrimitive) -> SwiftPrimitiveType {
        switch primitive {
        case .bool: return SwiftPrimitive<Bool>()
        case .double: return SwiftPrimitive<Double>()
        case .integer: return SwiftPrimitive<Int>()
        case .string: return SwiftPrimitive<String>()
        }
    }

    private func readArray(from array: JSONArray) throws -> SwiftArray {
        return SwiftArray(element: try readAnyType(from: array.element))
    }

    private func readEnum(from enumeration: JSONEnumeration) -> SwiftEnum {
        return SwiftEnum(
            name: enumeration.name,
            comment: enumeration.comment,
            cases: enumeration.values.map { value in
                SwiftEnum.Case(label: value, rawValue: value)
            },
            conformance: []
        )
    }

    private func readStruct(from object: JSONObject) throws -> SwiftStruct {
        /// Reads Struct properties.
        func readProperties(from objectProperties: [JSONObject.Property]) throws -> [SwiftStruct.Property] {
            /// Reads Struct property default value.
            func readDefaultValue(for objectProperty: JSONObject.Property) throws -> SwiftPropertyDefaultValue? {
                return objectProperty.defaultVaule.ifNotNil { value in
                    switch value {
                    case .integer(let intValue):
                        return intValue
                    case .string(let stringValue):
                        if objectProperty.type is JSONEnumeration {
                            return SwiftEnum.Case(label: stringValue, rawValue: stringValue)
                        } else {
                            return stringValue
                        }
                    }
                }
            }

            return try objectProperties.map { property in
                return SwiftStruct.Property(
                    name: property.name,
                    comment: property.comment,
                    type: try readAnyType(from: property.type),
                    isOptional: !property.isRequired,
                    isMutable: !property.isReadOnly,
                    defaultVaule: try readDefaultValue(for: property),
                    codingKey: property.name
                )
            }
        }

        return SwiftStruct(
            name: object.name,
            comment: object.comment,
            properties: try readProperties(from: object.properties),
            conformance: []
        )
    }
}
