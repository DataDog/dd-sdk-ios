/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Transforms `SwiftType` schemas into `ObjcInteropType` schemas.
internal class SwiftToObjcInteropTypeTransformer {
    /// `SwiftTypes` passed on input.
    private var inputSwiftTypes: [SwiftType] = []
    /// `ObjcInteropTypes` returned on output.
    private var outputObjcInteropTypes: [ObjcInteropType] = []

    func transform(swiftTypes: [SwiftType]) throws -> [ObjcInteropType] {
        self.inputSwiftTypes = swiftTypes
        self.outputObjcInteropTypes = []

        try takeRootSwiftStructs(from: swiftTypes)
            .forEach { rootStruct in
                let rootClass = ObjcInteropRootClass(bridgedSwiftStruct: rootStruct)
                outputObjcInteropTypes.append(rootClass)
                try generateTransitiveObjcInteropTypes(in: rootClass)
            }

        return outputObjcInteropTypes
    }

    // MARK: - Private

    private func generateTransitiveObjcInteropTypes(in objcClass: ObjcInteropClass) throws {
        // Generate property wrappers
        objcClass.objcPropertyWrappers = try objcClass.bridgedSwiftStruct.properties
            .map { swiftProperty in
                switch swiftProperty.type {
                case let swiftPrimitive as SwiftPrimitiveType:
                    let propertyWrapper = ObjcInteropPropertyWrapperManagingSwiftStructProperty(
                        owner: objcClass,
                        swiftProperty: swiftProperty
                    )
                    propertyWrapper.objcInteropType = try objcInteropType(for: swiftPrimitive)
                    return propertyWrapper
                case let swiftStruct as SwiftStruct:
                    let propertyWrapper = ObjcInteropPropertyWrapperAccessingNestedStruct(
                        owner: objcClass,
                        swiftProperty: swiftProperty
                    )
                    propertyWrapper.objcNestedClass = ObjcInteropTransitiveNestedClass(
                        owner: propertyWrapper,
                        bridgedSwiftStruct: swiftStruct
                    )
                    return propertyWrapper
                case let swiftEnum as SwiftEnum:
                    let propertyWrapper = ObjcInteropPropertyWrapperAccessingNestedEnum(
                        owner: objcClass,
                        swiftProperty: swiftProperty
                    )
                    propertyWrapper.objcNestedEnum = ObjcInteropNestedEnum(
                        owner: propertyWrapper,
                        bridgedSwiftEnum: swiftEnum
                    )
                    return propertyWrapper
                case let swiftArray as SwiftArray where swiftArray.element is SwiftEnum:
                    let propertyWrapper = ObjcInteropPropertyWrapperAccessingNestedEnumsArray(
                        owner: objcClass,
                        swiftProperty: swiftProperty
                    )
                    propertyWrapper.objcNestedEnumsArray = ObjcInteropEnumArray(
                        owner: propertyWrapper,
                        bridgedSwiftEnum: swiftArray.element as! SwiftEnum // swiftlint:disable:this force_cast
                    )
                    return propertyWrapper
                case let swiftArray as SwiftArray where swiftArray.element is SwiftPrimitiveType:
                    let propertyWrapper = ObjcInteropPropertyWrapperManagingSwiftStructProperty(
                        owner: objcClass,
                        swiftProperty: swiftProperty
                    )
                    propertyWrapper.objcInteropType = try objcInteropType(for: swiftArray)
                    return propertyWrapper
                case let swiftArray as SwiftArray where swiftArray.element is SwiftStruct:
                    let propertyWrapper = ObjcInteropPropertyWrapperAccessingNestedStructsArray(
                        owner: objcClass,
                        swiftProperty: swiftProperty
                    )
                    propertyWrapper.objcNestedClass = ObjcInteropNestedClass(
                        owner: propertyWrapper,
                        bridgedSwiftStruct: swiftArray.element as! SwiftStruct // swiftlint:disable:this force_cast
                    )
                    return propertyWrapper
                case let swiftDictionary as SwiftDictionary:
                    let propertyWrapper = ObjcInteropPropertyWrapperManagingSwiftStructProperty(
                        owner: objcClass,
                        swiftProperty: swiftProperty
                    )
                    propertyWrapper.objcInteropType = try objcInteropType(for: swiftDictionary)
                    return propertyWrapper
                case let swiftAssociatedTypeEnum as SwiftAssociatedTypeEnum:
                    let propertyWrapper = ObjcInteropPropertyWrapperAccessingNestedAssociatedTypeEnum(
                        owner: objcClass,
                        swiftProperty: swiftProperty
                    )

                    let objcAssociatedTypeEnum = ObjcInteropReferencedAssociatedTypeEnum(
                        owner: propertyWrapper,
                        bridgedSwiftAssociatedTypeEnum: swiftAssociatedTypeEnum
                    )

                    let associatedObjcInteropTypes: [ObjcInteropType] = try swiftAssociatedTypeEnum.cases.map { swiftEnumCase in
                        let objcInteropClass = try objcInteropType(for: swiftEnumCase.associatedType)

                        guard let objcInteropClass = objcInteropClass as? ObjcInteropNestedClass else {
                            return objcInteropClass
                        }

                        let objcNestedClass = ObjcInteropTransitiveNestedClass(
                            owner: propertyWrapper,
                            bridgedSwiftStruct: SwiftStruct(name: swiftAssociatedTypeEnum.name, properties: [], conformance: [])
                        )

                        let objcNestedAssociatedTypeEnumPropertyWrapper = ObjcInteropPropertyWrapperAccessingNestedAssociatedTypeEnum(
                            owner: objcNestedClass,
                            swiftProperty: propertyWrapper.bridgedSwiftProperty
                        )
                        objcNestedAssociatedTypeEnumPropertyWrapper.objcNestedClass = objcNestedClass // to retain the Objc Enum representation
                        objcNestedAssociatedTypeEnumPropertyWrapper.objcNestedAssociatedTypeEnum = objcAssociatedTypeEnum
                        objcNestedClass.objcPropertyWrappers = [objcNestedAssociatedTypeEnumPropertyWrapper]
                        objcInteropClass.parentProperty = objcNestedAssociatedTypeEnumPropertyWrapper

                        let objcPropertyWrappers: [ObjcInteropPropertyWrapper] =
                        try (swiftEnumCase.associatedType as? SwiftStruct)?.properties.map {
                            let objcNestedType = try objcInteropType(for: $0.type)

                            if let objcNestedType = objcNestedType as? ObjcInteropEnum {
                                let nestedPropertyWrapper = ObjcInteropPropertyWrapperAccessingNestedEnum(
                                    owner: objcInteropClass,
                                    swiftProperty: $0
                                )
                                nestedPropertyWrapper.objcNestedEnum = ObjcInteropNestedEnum(owner: nestedPropertyWrapper, bridgedSwiftEnum: objcNestedType.bridgedSwiftEnum)

                                return nestedPropertyWrapper
                            } else {
                                let nestedPropertyWrapper = ObjcInteropPropertyWrapperManagingSwiftStructProperty(
                                    owner: objcInteropClass,
                                    swiftProperty: $0
                                )

                                nestedPropertyWrapper.objcInteropType = objcNestedType
                                return nestedPropertyWrapper
                            }
                        } ?? []

                        objcInteropClass.objcPropertyWrappers = objcPropertyWrappers

                        return objcInteropClass
                    }

                    objcAssociatedTypeEnum.associatedObjcInteropTypes = associatedObjcInteropTypes
                    propertyWrapper.objcNestedAssociatedTypeEnum = objcAssociatedTypeEnum
                    return propertyWrapper
                case let swifTypeReference as SwiftTypeReference:
                    let referencedType = try resolve(swiftTypeReference: swifTypeReference)

                    switch referencedType {
                    case let swiftStruct as SwiftStruct:
                        let propertyWrapper = ObjcInteropPropertyWrapperAccessingNestedStruct(
                            owner: objcClass,
                            swiftProperty: swiftProperty
                        )
                        propertyWrapper.objcNestedClass = ObjcInteropReferencedTransitiveClass(
                            owner: propertyWrapper,
                            bridgedSwiftStruct: swiftStruct
                        )
                        return propertyWrapper
                    case let swiftEnum as SwiftEnum:
                        let propertyWrapper = ObjcInteropPropertyWrapperAccessingNestedEnum(
                            owner: objcClass,
                            swiftProperty: swiftProperty
                        )
                        propertyWrapper.objcNestedEnum = ObjcInteropReferencedEnum(
                            owner: propertyWrapper,
                            bridgedSwiftEnum: swiftEnum
                        )
                        return propertyWrapper
                    case let swiftAssociatedTypeEnum as SwiftAssociatedTypeEnum:
                        let propertyWrapper = ObjcInteropPropertyWrapperAccessingNestedAssociatedTypeEnum(
                            owner: objcClass,
                            swiftProperty: swiftProperty
                        )
                        propertyWrapper.objcNestedAssociatedTypeEnum = ObjcInteropReferencedAssociatedTypeEnum(
                            owner: propertyWrapper,
                            bridgedSwiftAssociatedTypeEnum: swiftAssociatedTypeEnum,
                            associatedObjcInteropTypes: try swiftAssociatedTypeEnum.cases.map { swiftEnumCase in
                                try objcInteropType(for: swiftEnumCase.associatedType)
                            }
                        )
                        return propertyWrapper
                    default:
                        throw Exception.illegal("Illegal reference type: \(swifTypeReference)")
                    }
                default:
                    throw Exception.unimplemented(
                        "Cannot generate @objc property wrapper for: \(type(of: swiftProperty.type))"
                    )
                }
            }

        try objcClass.objcPropertyWrappers
            .compactMap { $0 as? ObjcInteropPropertyWrapperForTransitiveType }
            .forEach { propertyWrapper in
                // Store `ObjcInteropTypes` created for property wrappers
                outputObjcInteropTypes.append(propertyWrapper.objcTransitiveType)
                if let transitiveClass = propertyWrapper.objcTransitiveType as? ObjcInteropClass {
                    // Recursively generate property wrappers for each transitive `ObjcInteropClass`
                    try generateTransitiveObjcInteropTypes(in: transitiveClass)
                }
            }
    }

    private func objcInteropType(for swiftType: SwiftType) throws -> ObjcInteropType {
        switch swiftType {
        case is SwiftPrimitive<Bool>,
             is SwiftPrimitive<Double>,
             is SwiftPrimitive<Int>,
             is SwiftPrimitive<Int64>:
            return ObjcInteropNSNumber(swiftType: swiftType)
        case let swiftCodable as SwiftCodable:
            return ObjcInteropAny(swiftType: swiftCodable)
        case let swiftEncodable as SwiftEncodable:
            return ObjcInteropAny(swiftType: swiftEncodable)
        case let swiftString as SwiftPrimitive<String>:
            return ObjcInteropNSString(swiftString: swiftString)
        case let swiftArray as SwiftArray:
            return ObjcInteropNSArray(element: try objcInteropType(for: swiftArray.element))
        case let swiftDictionary as SwiftDictionary:
            return ObjcInteropNSDictionary(
                key: try objcInteropType(for: swiftDictionary.key),
                value: try objcInteropType(for: swiftDictionary.value)
            )
        case let swiftStruct as SwiftStruct:
            return ObjcInteropNestedClass(owner: nil, bridgedSwiftStruct: swiftStruct)
        case let swiftEnum as SwiftEnum:
            return ObjcInteropEnum(bridgedSwiftEnum: swiftEnum)
        default:
            throw Exception.unimplemented(
                "Cannot create `ObjcInteropType` type for \(type(of: swiftType))."
            )
        }
    }

    // MARK: - Helpers

    /// Filters out given `SwiftTypes` by removing all types referenced using `SwiftReferenceType`.
    ///
    /// For example, given swift schema this Swift code:
    ///
    ///         struct Foo {
    ///            let shared: SharedStruct
    ///         }
    ///
    ///         struct Bar {
    ///            let shared: SharedStruct
    ///         }
    ///
    ///         struct SharedStruct {
    ///            // ...
    ///         }
    ///
    /// if both `Foo` and `Bar` use `SwiftReferenceType(referencedTypeName: "SharedStruct")`,
    /// the returned array will contain only `Foo` and `Bar` schemas.
    private func takeRootSwiftStructs(from swiftTypes: [SwiftType]) -> [SwiftStruct] {
        let referencedTypeNames = swiftTypes
            .compactMap { $0 as? SwiftStruct } // only `SwiftStructs` may contain `SwiftReferenceType`
            .flatMap { $0.recursiveSwiftTypeReferences }
            .map { $0.referencedTypeName }
            .asSet()

        return swiftTypes
            .compactMap { $0 as? SwiftStruct }
            .filter { !referencedTypeNames.contains($0.typeName!) } // swiftlint:disable:this force_unwrapping
    }

    /// Searches `SwiftTypes` passed on input and returns the one described by given `SwiftTypeReference`.
    private func resolve(swiftTypeReference: SwiftTypeReference) throws -> SwiftType {
        return try inputSwiftTypes
            .first { $0.typeName == swiftTypeReference.referencedTypeName }
            .unwrapOrThrow(.inconsistency("Cannot find referenced type \(swiftTypeReference.referencedTypeName)"))
    }
}

// MARK: - Reflection Helpers

private extension SwiftStruct {
    /// Returns `SwiftTypeReferences` used by this or nested structs.
    var recursiveSwiftTypeReferences: [SwiftTypeReference] {
        let referencesInThisStruct = properties
            .compactMap { $0.type as? SwiftTypeReference }
        let referencesInNestedStructs = properties
            .compactMap { $0.type as? SwiftStruct }
            .flatMap { $0.recursiveSwiftTypeReferences }
        return referencesInThisStruct + referencesInNestedStructs
    }
}
