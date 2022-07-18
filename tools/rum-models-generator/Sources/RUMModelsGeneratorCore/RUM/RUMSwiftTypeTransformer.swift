/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Transforms `SwiftTypes` for RUM code generation.
internal class RUMSwiftTypeTransformer {
    /// Types which will shared between all input `types`. Sharing means detaching those types from nested declaration
    /// and putting them at the root level of the resultant `types` array, so the type can be printed without being nested.
    private let sharedTypeNames = [
        "RUMConnectivity",
        "RUMUser",
        "RUMMethod",
        "RUMEventAttributes",
        "RUMCITest",
        "RUMDevice",
        "RUMOperatingSystem",
    ]

    /// `RUMDataModel` protocol, implemented by all RUM models.
    private let rumDataModelProtocol = SwiftProtocol(name: "RUMDataModel", conformance: [codableProtocol])

    /// Transformation context. It pushes `SwiftTypes` to and from the `context.stack`
    /// so we can know the current level of recursive transformation.
    private let context = TransformationContext<SwiftType>()

    func transform(types: [SwiftType]) throws -> [SwiftType] {
        sharedRootTypes = []

        precondition(context.current == nil)
        let transformed = try types.map { try transformAny(swiftType: $0) }
        precondition(context.current == nil)

        return transformed + sharedRootTypes
    }

    // MARK: - Type Transformations

    private func transformAny(swiftType: SwiftType) throws -> SwiftType {
        context.enter(swiftType)
        defer { context.leave() }

        switch swiftType {
        case let primitive as SwiftPrimitiveType:
            return transform(primitive: primitive)
        case let array as SwiftArray:
            return try transform(array: array)
        case let dictionary as SwiftDictionary:
            return transform(dictionary: dictionary)
        case let `enum` as SwiftEnum:
            let transformed = transform(enum: `enum`)
            return isSharedType(transformed) ? try replaceWithSharedTypeReference(transformed) : transformed
        case let associatedTypeEnum as SwiftAssociatedTypeEnum:
            let transformed = transform(associatedTypeEnum: associatedTypeEnum)
            return isSharedType(transformed) ? try replaceWithSharedTypeReference(transformed) : transformed
        case let `struct` as SwiftStruct:
            let transformed = try transform(struct: `struct`)
            return isSharedType(transformed) ? try replaceWithSharedTypeReference(transformed) : transformed
        default:
            throw Exception.unimplemented("RUM transformation is not implemented for \(type(of: swiftType))")
        }
    }

    private func transform(primitive: SwiftPrimitiveType) -> SwiftPrimitiveType {
        if primitive is SwiftPrimitive<Int> {
            return SwiftPrimitive<Int64>() // Replace all `Int` with `Int64`
        } else {
            return primitive
        }
    }

    private func transform(dictionary: SwiftDictionary) -> SwiftDictionary {
        var dictionary = dictionary
        dictionary.value = transform(primitive: dictionary.value)
        return dictionary
    }

    private func transform(array: SwiftArray) throws -> SwiftArray {
        var array = array
        array.element = try transformAny(swiftType: array.element)
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

    private func transform(associatedTypeEnum: SwiftAssociatedTypeEnum) -> SwiftAssociatedTypeEnum {
        func transform(enumCase: SwiftAssociatedTypeEnum.Case) -> SwiftAssociatedTypeEnum.Case {
            var enumCase = enumCase
            enumCase.label = format(enumCaseName: enumCase.label)
            return enumCase
        }

        var associatedTypeEnum = associatedTypeEnum
        associatedTypeEnum.name = format(enumName: associatedTypeEnum.name)
        associatedTypeEnum.cases = associatedTypeEnum.cases.map { transform(enumCase: $0) }
        associatedTypeEnum.conformance = [codableProtocol] // Conform all enums to `Codable`
        return associatedTypeEnum
    }

    private func transform(`struct`: SwiftStruct) throws -> SwiftStruct {
        func transform(structProperty: SwiftStruct.Property) throws -> SwiftStruct.Property {
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
            structProperty.type = try transformAny(swiftType: structProperty.type)
            structProperty.defaultValue = structProperty.defaultValue.ifNotNil { transform(defaultValue: $0) }
            return structProperty
        }

        var `struct` = `struct`
        `struct`.name = format(structName: `struct`.name)
        `struct`.properties = try `struct`.properties
            .map { try transform(structProperty: $0) }
        if context.parent == nil {
            `struct`.conformance = [rumDataModelProtocol] // Conform root structs to `RUMDataModel`
        } else {
            `struct`.conformance = [codableProtocol] // Conform other structs to `Codable`
        }
        return `struct`
    }

    // MARK: - Naming Conventions

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
            let parentStruct = context.predecessor(matching: { $0 is SwiftStruct }) as? SwiftStruct
            let parentTypeName = parentStruct?.name ?? ""
            fixedName = format(structName: parentTypeName) + fixedName
        }

        if fixedName == "Connectivity" {
            fixedName = "RUMConnectivity"
        }

        if fixedName == "USR" {
            fixedName = "RUMUser"
        }

        if fixedName == "Method" {
            fixedName = "RUMMethod"
        }

        if fixedName == "Context" {
            fixedName = "RUMEventAttributes"
        }

        if fixedName == "CiTest" {
            fixedName = "RUMCITest"
        }

        if fixedName == "Device" {
            fixedName = "RUMDevice"
        }

        if fixedName == "OS" {
            fixedName = "RUMOperatingSystem"
        }

        return fixedName
    }

    // MARK: - Shared Types

    private var sharedRootTypes: [SwiftType] = []

    /// Returns `true` if this `type` is configured to be shared.
    private func isSharedType(_ type: SwiftType) -> Bool {
        if let name = type.typeName {
            return sharedTypeNames.contains(name)
        } else {
            return false
        }
    }

    /// Detaches given `type` from nested declaration by replacing it with `SwiftTypeReference` and
    /// appending to `sharedRootTypes`.
    private func replaceWithSharedTypeReference(_ type: SwiftType) throws -> SwiftTypeReference {
        guard let name = type.typeName else {
            throw Exception.illegal("Type \(type) cannot be shared.")
        }

        if let existing = sharedRootTypes.first(where: { $0.typeName == name }) {
            // If a type with given name is already declared as shared, its definition must be
            // equal to `type`, otherwise sharing is not possible.
            guard existing == type else {
                throw Exception.inconsistency(
                    """
                    \(type) and \(existing) cannot be printed as a shared root type because their definitions are different.
                    """
                )
            }
        } else {
            sharedRootTypes.append(type)
        }

        return SwiftTypeReference(referencedTypeName: name)
    }
}
