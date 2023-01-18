/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Adjusts naming and structure of generated code to common Swift conventions. This includes:
/// - 'UpperCamelCase' naming for types,
/// - 'lowerCamelCase' naming for `struct` properties,
/// - `Codable` conformance for all `structs` and `enums`.
///
/// On top of that, this decorator implements capability of detaching some nested types and sharing their implementation.
/// For example, if `Foo.Bar` and `Bizz.Bar` use the same schema for nested `Bar` structure, and "Bar" is listed
/// in `sharedTypeNames` configuration,  then `Bar` will be transformed to a root type.
open class SwiftCodeDecorator: CodeDecorator {
    /// Names of types that will be detached from their nested declaration
    /// and put at the root level in decorated code..
    public let sharedTypeNames: [String]

    /// Currently detached shared types.
    private var sharedRootTypes: [SwiftType] = []

    /// Transformation context. It pushes `SwiftTypes` to and from the `context.stack`
    /// so it is possible to track the current level of recursive transformation.
    public let context = TransformationContext<SwiftType>()

    /// Initializer.
    /// - Parameter sharedTypeNames: names of types that will be detached from their nested declaration
    /// and put at the root level in decorated code. If names are additionally customised, use the final names for this setting.
    public init(sharedTypeNames: [String] = []) {
        self.sharedTypeNames = sharedTypeNames
    }

    // MARK: - CodeDecorator

    public func decorate(code: GeneratedCode) throws -> GeneratedCode {
        sharedRootTypes = []

        return GeneratedCode(
            swiftTypes: try transform(types: code.swiftTypes)
        )
    }

    // MARK: - Recursive transformation

    private func transform(types: [SwiftType]) throws -> [SwiftType] {
        precondition(context.current == nil)
        let transformed = try types.map { try transformAny(swiftType: $0) }
        precondition(context.current == nil)
        return transformed + sharedRootTypes
    }

    open func transformAny(swiftType: SwiftType) throws -> SwiftType {
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
            let transformed = try transform(associatedTypeEnum: associatedTypeEnum)
            return isSharedType(transformed) ? try replaceWithSharedTypeReference(transformed) : transformed
        case let `struct` as SwiftStruct:
            let transformed = try transform(struct: `struct`)
            return isSharedType(transformed) ? try replaceWithSharedTypeReference(transformed) : transformed
        default:
            throw Exception.unimplemented("Decoration is not implemented for \(type(of: swiftType))")
        }
    }

    open func transform(primitive: SwiftPrimitiveType) -> SwiftPrimitiveType {
        return primitive
    }

    open func transform(dictionary: SwiftDictionary) -> SwiftDictionary {
        var dictionary = dictionary
        dictionary.value = transform(primitive: dictionary.value)
        return dictionary
    }

    open func transform(array: SwiftArray) throws -> SwiftArray {
        var array = array
        array.element = try transformAny(swiftType: array.element)
        return array
    }

    open func transform(`enum`: SwiftEnum) -> SwiftEnum {
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

    open func transform(associatedTypeEnum: SwiftAssociatedTypeEnum) throws -> SwiftAssociatedTypeEnum {
        func transform(enumCase: SwiftAssociatedTypeEnum.Case) throws -> SwiftAssociatedTypeEnum.Case {
            var enumCase = enumCase
            enumCase.label = format(enumCaseName: enumCase.label)
            enumCase.associatedType = try transformAny(swiftType: enumCase.associatedType)
            return enumCase
        }

        var associatedTypeEnum = associatedTypeEnum
        associatedTypeEnum.name = format(enumName: associatedTypeEnum.name)
        associatedTypeEnum.cases = try associatedTypeEnum.cases.map { try transform(enumCase: $0) }
        associatedTypeEnum.conformance = [codableProtocol] // Conform all enums to `Codable`
        return associatedTypeEnum
    }

    open func transform(`struct`: SwiftStruct) throws -> SwiftStruct {
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
        `struct`.properties = try `struct`.properties.map { try transform(structProperty: $0) }
        `struct`.conformance = [codableProtocol] // Conform all structs to `Codable`
        return `struct`
    }

    // MARK: - Naming Conventions

    open func format(structName: String) -> String {
        fix(typeName: structName.upperCamelCased)
    }

    open func format(propertyName: String) -> String {
        propertyName.lowerCamelCased
    }

    open func format(enumName: String) -> String {
        fix(typeName: enumName.upperCamelCased)
    }

    open func format(enumCaseName: String) -> String {
        return enumCaseName.lowerCamelCased
    }

    /// Enables fixing names in generated code.
    /// - Parameter typeName: the name of a type (`struct` or `enum`) that needs to be fixed
    /// - Returns: the fixed name
    ///
    /// In override, make sure to call the super implementaiton first, as it applies common fixes for producing idiomatic Swift code.
    open func fix(typeName: String) -> String {
        var fixedName = typeName

        // If the type name collides with Swift `Type` keyword, prefix it with parent type name.
        if fixedName == "Type" {
            let parentStruct = context.predecessor(matching: { $0 is SwiftStruct }) as? SwiftStruct
            let parentTypeName = parentStruct?.name ?? ""
            fixedName = format(structName: parentTypeName) + fixedName
        }

        return fixedName
    }

    // MARK: - Sharing Types

    /// Returns `true` if this `type` is configured to be shared and should be detached
    /// from its current (nested) level to become a root type.
    private func isSharedType(_ type: SwiftType) -> Bool {
        if let name = type.typeName {
            return sharedTypeNames.contains(name)
        } else {
            return false
        }
    }

    /// Detaches given `type` from its current (nested) level by replacing it with `SwiftTypeReference` and
    /// appending to `sharedRootTypes`. At the end, `sharedRootTypes` will be transformed to root types.
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
