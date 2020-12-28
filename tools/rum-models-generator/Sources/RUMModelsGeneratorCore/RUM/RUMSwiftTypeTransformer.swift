/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Transforms `SwiftTypes` for RUM code generation.
internal class RUMSwiftTypeTransformer: TypeTransformer<SwiftType> {
    private let rumDataModelProtocol = SwiftProtocol(name: "RUMDataModel", conformance: [codableProtocol])

    override func transform(type: SwiftType) -> SwiftType {
        precondition(context.current == nil)
        let transformed = transformAny(type: type)
        precondition(context.current == nil)
        return transformed
    }

    // MARK: - Private

    private func transformAny(type: SwiftType) -> SwiftType {
        context.enter(type)
        defer { context.leave() }

        switch type {
        case let primitive as SwiftPrimitiveType:
            return transform(primitive: primitive)
        case let array as SwiftArray:
            return transform(array: array)
        case let `enum` as SwiftEnum:
            return transform(enum: `enum`)
        case let `struct` as SwiftStruct:
            return transform(struct: `struct`)
        default:
            return type
        }
    }

    private func transform(primitive: SwiftPrimitiveType) -> SwiftPrimitiveType {
        if primitive is SwiftPrimitive<Int> {
            return SwiftPrimitive<Int64>() // Replace all `Int` with `Int64`
        } else {
            return primitive
        }
    }

    private func transform(array: SwiftArray) -> SwiftArray {
        var array = array
        array.element = transformAny(type: array.element)
        return array
    }

    private func transform(`enum`: SwiftEnum) -> SwiftEnum {
        func transform(enumCase: SwiftEnum.Case) -> SwiftEnum.Case {
            var enumCase = enumCase
            enumCase.label = format(enumCaseName: enumCase.label)
            return enumCase
        }

        var `enum` = `enum`
        `enum`.name = format(enumName: `enum`.name)
        `enum`.cases = `enum`.cases.map { transform(enumCase: $0) }
        `enum`.conformance = [codableProtocol] // Conform all enums to `Codable`
        return `enum`
    }

    private func transform(`struct`: SwiftStruct) -> SwiftStruct {
        func transform(structProperty: SwiftStruct.Property) -> SwiftStruct.Property {
            func transform(defaultValue: SwiftPropertyDefaultValue) -> SwiftPropertyDefaultValue {
                if var enumCase = defaultValue as? SwiftEnum.Case {
                    enumCase.label = format(enumCaseName: enumCase.label)
                    return enumCase
                } else {
                    return defaultValue
                }
            }

            var structProperty = structProperty
            structProperty.name = format(propertyName: structProperty.name)
            structProperty.type = transformAny(type: structProperty.type)
            structProperty.defaultVaule = structProperty.defaultVaule.ifNotNil { transform(defaultValue: $0) }
            return structProperty
        }

        var `struct` = `struct`
        `struct`.name = format(structName: `struct`.name)
        `struct`.properties = `struct`.properties.map { transform(structProperty: $0) }
        if context.parent == nil {
            `struct`.conformance = [rumDataModelProtocol] // Conform root structs to `RUMDataModel`
        } else {
            `struct`.conformance = [codableProtocol] // Conform other structs to `Codable`
        }
        return `struct`
    }

    private func format(structName: String) -> String {
        fix(typeName: structName.upperCamelCased)
    }

    private func format(propertyName: String) -> String {
        propertyName.lowerCamelCased
    }

    private func format(enumName: String) -> String {
        fix(typeName: enumName.upperCamelCased)
    }

    private func format(enumCaseName: String) -> String {
        // When generating enum cases for Resource's HTTP method, force lowercase
        // (`.get`, `.post`, ...)
        if (context.current as? SwiftEnum)?.name.lowercased() == "method" {
            return enumCaseName.lowercased()
        }

        return enumCaseName.lowerCamelCased
    }

    /// Some RUM type names need additional fix to not conflict with Swift keywords (like `Type`) or just to look better.
    private func fix(typeName: String) -> String {
        var fixedName = typeName

        // If the type name uses an abbreviation, keep it uppercased.
        if fixedName.count <= 3 {
            fixedName = typeName.uppercased()
        }

        // If the name starts with "rum" (any-cased), ensure it gets uppercased.
        if fixedName.lowercased().hasPrefix("rum") {
            fixedName = fixedName.prefix(3).uppercased() + fixedName.suffix(fixedName.count - 3)
        }

        // If the type name collides with Swift `Type` keyword, prefix it with parent type name.
        if fixedName == "Type" {
            let parentTypeName = (context.parent as? SwiftStruct)?.name ?? ""
            fixedName = format(structName: parentTypeName) + fixedName
        }

        return fixedName
    }
}
