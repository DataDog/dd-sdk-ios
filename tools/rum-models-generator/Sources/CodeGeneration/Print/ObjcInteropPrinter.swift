/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

/// Generates Swift code for Obj-c interoperability for given `ObjcInteropType` schemas.
///
/// E.g. given `ObjcInteropType` describing Swift struct:
///
///     public struct Foo {
///         public var string = "foo"
///         public let integer = 123
///     }
///
/// it prints it's Obj-c interoperability wrapper:
///
///     @objc
///     public class DDFoo: NSObject {
///         internal var foo: Foo
///
///         internal init(foo: Foo) {
///             self.foo = foo
///         }
///
///         @objc
///         public var string: String {
///             set { foo.string = newValue }
///             get { foo.string }
///         }
///
///         @objc
///         public var integer: NSNumber { foo.integer as NSNumber }
///     }
///
public class ObjcInteropPrinter: BasePrinter, CodePrinter {
    public init(objcTypeNamesPrefix: String) {
        self.objcTypeNamesPrefix = objcTypeNamesPrefix
    }

    // MARK: - CodePrinter

    public func print(code: GeneratedCode) throws -> String {
        let objcInteropTransformer = SwiftToObjcInteropTypeTransformer()
        let objcInteropTypes = try objcInteropTransformer.transform(swiftTypes: code.swiftTypes)
        return try print(objcInteropTypes: objcInteropTypes)
    }

    // MARK: - Internal

    /// The prefix used for types exposed to Obj-c.
    private let objcTypeNamesPrefix: String

    func print(objcInteropTypes: [ObjcInteropType]) throws -> String {
        reset()
        try objcInteropTypes.forEach { try print(objcInteropType: $0) }
        return output
    }

    // MARK: - Printing Objc Classes and Enums

    private func print(objcInteropType: ObjcInteropType) throws {
        switch objcInteropType {
        case let rootClass as ObjcInteropRootClass:
            try print(objcInteropRootClass: rootClass)
        case let nestedClass as ObjcInteropNestedClass:
            try print(objcInteropNestedClass: nestedClass)
        case let nestedTransitiveClass as ObjcInteropTransitiveNestedClass:
            try print(objcInteropNestedTransitiveClass: nestedTransitiveClass)
        case let enumeration as ObjcInteropEnum:
            try print(objcInteropEnum: enumeration)
        case let nestedAssociatedTypeEnum as ObjcInteropAssociatedTypeEnum:
            try print(objcInteropNestedAssociatedTypeEnum: nestedAssociatedTypeEnum)
        default:
            throw Exception.unimplemented("Cannot print `ObjcInteropType`: \(type(of: objcInteropType))")
        }
    }

    private func print(objcInteropRootClass: ObjcInteropRootClass) throws {
        let className = objcTypeNamesPrefix + objcInteropRootClass.objcTypeName
        writeEmptyLine()
        writeLine("@objc(\(className.objcNaming))")
        writeLine("@objcMembers")
        writeLine("@_spi(objc)")
        writeLine("public class \(className): NSObject {")
        indentRight()
            writeLine("public internal(set) var swiftModel: \(objcInteropRootClass.swiftTypeName)")
            writeLine("internal var root: \(className) { self }")
            writeEmptyLine()
            writeLine("public init(swiftModel: \(objcInteropRootClass.swiftTypeName)) {")
            indentRight()
                writeLine("self.swiftModel = swiftModel")
            indentLeft()
            writeLine("}")
            try objcInteropRootClass.objcPropertyWrappers.forEach { propertyWrapper in
                try print(objcInteropPropertyWrapper: propertyWrapper)
            }
        indentLeft()
        writeLine("}")
    }

    private func print(objcInteropNestedClass: ObjcInteropNestedClass) throws {
        let className = objcTypeNamesPrefix + objcInteropNestedClass.objcTypeName
        writeEmptyLine()
        writeLine("@objc(\(className.objcNaming))")
        writeLine("@objcMembers")
        writeLine("@_spi(objc)")
        writeLine("public class \(className): NSObject {")
        indentRight()
            writeLine("internal var swiftModel: \(objcInteropNestedClass.swiftTypeName)")
        writeLine("internal var root: \(className) { self }")
            writeEmptyLine()
            writeLine("internal init(swiftModel: \(objcInteropNestedClass.swiftTypeName)) {")
            indentRight()
                writeLine("self.swiftModel = swiftModel")
            indentLeft()
            writeLine("}")
            try objcInteropNestedClass.objcPropertyWrappers.forEach { propertyWrapper in
                try print(objcInteropPropertyWrapper: propertyWrapper)
            }
        indentLeft()
        writeLine("}")
    }

    private func print(objcInteropNestedTransitiveClass: ObjcInteropTransitiveNestedClass) throws {
        let className = objcTypeNamesPrefix + objcInteropNestedTransitiveClass.objcTypeName
        let rootClassName = objcTypeNamesPrefix + objcInteropNestedTransitiveClass.objcRootClass.objcTypeName
        writeEmptyLine()
        writeLine("@objc(\(className.objcNaming))")
        writeLine("@objcMembers")
        writeLine("@_spi(objc)")
        writeLine("public class \(className): NSObject {")
        indentRight()
            writeLine("internal let root: \(rootClassName)")
            writeEmptyLine()
            writeLine("internal init(root: \(rootClassName)) {")
            indentRight()
                writeLine("self.root = root")
            indentLeft()
            writeLine("}")
            try objcInteropNestedTransitiveClass.objcPropertyWrappers.forEach { propertyWrapper in
                try print(objcInteropPropertyWrapper: propertyWrapper)
            }
        indentLeft()
        writeLine("}")
    }

    private func print(objcInteropEnum: ObjcInteropEnum) throws {
        let enumName = objcTypeNamesPrefix + objcInteropEnum.objcTypeName
        let swiftEnum = objcInteropEnum.bridgedSwiftEnum
        let managesOptionalEnum = objcInteropEnum.parentProperty.bridgedSwiftProperty.isOptional
        let objcEnumOptionality = managesOptionalEnum ? "?" : ""
        writeEmptyLine()
        writeLine("@objc(\(enumName.objcNaming))")
        writeLine("@_spi(objc)")
        writeLine("public enum \(enumName): Int {")
        indentRight()
            writeLine("internal init(swift: \(objcInteropEnum.swiftTypeName)\(objcEnumOptionality)) {")
            indentRight()
                writeLine("switch swift {")
                if managesOptionalEnum {
                    writeLine("case nil: self = .none")
                }
                swiftEnum.cases.forEach { enumCase in
                    writeLine("case .\(enumCase.backtickLabel)\(objcEnumOptionality): self = .\(enumCase.backtickLabel)")
                }
                writeLine("}")
            indentLeft()
            writeLine("}")
            writeEmptyLine()
            writeLine("internal var toSwift: \(objcInteropEnum.swiftTypeName)\(objcEnumOptionality) {")
            indentRight()
                writeLine("switch self {")
                if managesOptionalEnum {
                    writeLine("case .none: return nil")
                }
                swiftEnum.cases.forEach { enumCase in
                    writeLine("case .\(enumCase.backtickLabel): return .\(enumCase.backtickLabel)")
                }
                writeLine("}")
            indentLeft()
            writeLine("}")
            writeEmptyLine()
            if managesOptionalEnum {
                writeLine("case none")
            }
            swiftEnum.cases.forEach { enumCase in
                writeLine("case \(enumCase.label)")
            }
        indentLeft()
        writeLine("}")
    }

    private func print(objcInteropNestedAssociatedTypeEnum: ObjcInteropAssociatedTypeEnum) throws {
        let propertyWrapper = objcInteropNestedAssociatedTypeEnum.parentProperty
        let swiftProperty = propertyWrapper.bridgedSwiftProperty
        let className = objcTypeNamesPrefix + objcInteropNestedAssociatedTypeEnum.objcTypeName
        let rootClassName = objcTypeNamesPrefix + objcInteropNestedAssociatedTypeEnum.objcRootClass.objcTypeName

        if swiftProperty.mutability == .mutable {
            throw Exception.unimplemented("Generating mutable `ObjcInteropAssociatedTypeEnum` is not supported: \(swiftProperty.type).")
        }

        writeEmptyLine()
        writeLine("@objc(\(className.objcNaming))")
        writeLine("@objcMembers")
        writeLine("@_spi(objc)")
        writeLine("public class \(className): NSObject {")
        indentRight()
        writeLine("internal let root: \(rootClassName)")
            writeEmptyLine()
            writeLine("internal init(root: \(rootClassName)) {")
            indentRight()
                writeLine("self.root = root")
            indentLeft()
            writeLine("}")

            // Generate optional computed `var` for each enumeration `case` and its associated value:
            try zip(
                objcInteropNestedAssociatedTypeEnum.bridgedSwiftAssociatedTypeEnum.cases,
                objcInteropNestedAssociatedTypeEnum.associatedObjcInteropTypes
            ).forEach { swiftEnumCase, objcInteropAssociatedType in
                let objcTypeName = try objcInteropTypeName(for: objcInteropAssociatedType)
                let asObjcCast = try swiftToObjcCast(for: objcInteropAssociatedType, isOptional: swiftProperty.isOptional) ?? ""
                let caseName = swiftEnumCase.backtickLabel

                writeEmptyLine()
                writeLine("public var \(caseName): \(objcTypeName)? {")
                indentRight()
                    writeLine("guard case .\(caseName)(let value) = root.swiftModel.\(propertyWrapper.keyPath) else {")
                    indentRight()
                        writeLine("return nil")
                    indentLeft()
                    writeLine("}")
                    writeLine("return value\(asObjcCast)")
                indentLeft()
                writeLine("}")
            }
        indentLeft()
        writeLine("}")
    }

    // MARK: - Printing Property Wrappers

    private func print(objcInteropPropertyWrapper: ObjcInteropPropertyWrapper) throws {
        writeEmptyLine()

        switch objcInteropPropertyWrapper {
        case let wrapper as ObjcInteropPropertyWrapperAccessingNestedStruct:
            try printPropertyAccessingNestedClass(wrapper)
        case let wrapper as ObjcInteropPropertyWrapperAccessingNestedEnum:
            try printPropertyAccessingNestedEnum(wrapper)
        case let wrapper as ObjcInteropPropertyWrapperAccessingNestedEnumsArray:
            try printPropertyAccessingNestedEnumArray(wrapper)
        case let wrapper as ObjcInteropPropertyWrapperAccessingNestedStructsArray:
            try printPropertyAccessingNestedStructArray(wrapper)
        case let wrapper as ObjcInteropPropertyWrapperManagingSwiftStructProperty:
            try printPrimitivePropertyWrapper(wrapper)
        case let wrapper as ObjcInteropPropertyWrapperAccessingNestedAssociatedTypeEnum:
            try printPropertyAccessingNestedAssociatedTypeEnum(wrapper)
        default:
            throw Exception.illegal("Unrecognized property wrapper: \(type(of: objcInteropPropertyWrapper))")
        }
    }

    private func printPropertyAccessingNestedClass(_ propertyWrapper: ObjcInteropPropertyWrapperAccessingNestedStruct) throws {
        let nestedObjcClass = propertyWrapper.objcNestedClass! // swiftlint:disable:this force_unwrapping

        // Generate accessor to the referenced wrapper, e.g.:
        // ```
        // @objc public var bar: DDFooBar? {
        //     root.swiftModel.bar != nil ? DDFooBar(root: root) : nil
        // }
        // ```
        let swiftProperty = propertyWrapper.bridgedSwiftProperty
        let objcPropertyName = swiftProperty.backtickName
        let objcPropertyOptionality = swiftProperty.isOptional ? "?" : ""
        let objcClassName = objcTypeNamesPrefix + nestedObjcClass.objcTypeName
        writeLine("public var \(objcPropertyName): \(objcClassName)\(objcPropertyOptionality) {")
        indentRight()
            if swiftProperty.isOptional {
                // The property is optional, so the accessor must be returned only if the wrapped value is `!= nil`, e.g.:
                // ```
                // root.swiftModel.bar != nil ? DDFooBar(root: root) : nil
                // ```
                writeLine("root.swiftModel.\(propertyWrapper.keyPath) != nil ? \(objcClassName)(root: root) : nil")
            } else {
                // The property is non-optional, so accessor can be provided without considering `nil` value:
                // ```
                // DDFooBar(root: root)
                // ```
                writeLine("\(objcClassName)(root: root)")
            }
        indentLeft()
        writeLine("}")
    }

    private func printPropertyAccessingNestedEnum(_ propertyWrapper: ObjcInteropPropertyWrapperAccessingNestedEnum) throws {
        let nestedObjcEnum = propertyWrapper.objcNestedEnum! // swiftlint:disable:this force_unwrapping

        // Generate getter and setter for managed enum, e.g.:
        // ```
        // @objc public var enumeration: DDFooEnumeration {
        //    set { root.swiftModel.enumeration = newValue.toSwift }
        //    get { .init(swift: root.swiftModel.enumeration) }
        // }
        // ```
        let swiftProperty = propertyWrapper.bridgedSwiftProperty
        let objcPropertyName = swiftProperty.backtickName
        let objcEnumName = objcTypeNamesPrefix + nestedObjcEnum.objcTypeName

        switch swiftProperty.mutability {
        case .mutable:
            writeLine("public var \(objcPropertyName): \(objcEnumName) {")
            indentRight()
                writeLine("set { root.swiftModel.\(propertyWrapper.keyPath) = newValue.toSwift }")
                writeLine("get { .init(swift: root.swiftModel.\(propertyWrapper.keyPath)) }")
            indentLeft()
            writeLine("}")
        case .immutable, .mutableInternally:
            writeLine("public var \(objcPropertyName): \(objcEnumName) {")
            indentRight()
                writeLine(".init(swift: root.swiftModel.\(propertyWrapper.keyPath))")
            indentLeft()
            writeLine("}")
        }
    }

    private func printPropertyAccessingNestedEnumArray(_ propertyWrapper: ObjcInteropPropertyWrapperAccessingNestedEnumsArray) throws {
        let nestedObjcEnumArray = propertyWrapper.objcNestedEnumsArray! // swiftlint:disable:this force_unwrapping

        // Generate getter for managed enum array.
        // Because `[Enum]` cannot be exposed to Objc directly, we map each value to its `.rawValue`
        // representation (which is `Int` for all `@objc` enums), e.g.:
        // ```
        // @objc public var options: [Int] {
        //     root.swiftModel.bar.options.map { DDFooOptions(swift: $0).rawValue }
        // }
        // ```
        let swiftProperty = propertyWrapper.bridgedSwiftProperty
        let objcPropertyName = swiftProperty.backtickName
        let objcPropertyOptionality = swiftProperty.isOptional ? "?" : ""
        let objcEnumName = objcTypeNamesPrefix + nestedObjcEnumArray.objcTypeName

        if swiftProperty.mutability == .mutable {
            throw Exception.unimplemented("Generating setter for `ObjcInteropEnumArray` is not supported: \(swiftProperty.type).")
        }

        writeLine("public var \(objcPropertyName): [Int]\(objcPropertyOptionality) {")
        indentRight()
            writeLine("root.swiftModel.\(propertyWrapper.keyPath)\(objcPropertyOptionality).map { \(objcEnumName)(swift: $0).rawValue }")
        indentLeft()
        writeLine("}")
    }

    private func printPropertyAccessingNestedStructArray(_ propertyWrapper: ObjcInteropPropertyWrapperAccessingNestedStructsArray) throws {
        let nestedObjcClass = propertyWrapper.objcNestedClass! // swiftlint:disable:this force_unwrapping

        // Generate getter for managed structs array.
        // ```
        // @objc public var bars: [DDBar] {
        //     root.swiftModel.bars.map { DDBar(swiftModel: $0) }
        // }
        // ```
        let swiftProperty = propertyWrapper.bridgedSwiftProperty
        let objcPropertyName = swiftProperty.backtickName
        let objcPropertyOptionality = swiftProperty.isOptional ? "?" : ""
        let objcClassName = objcTypeNamesPrefix + nestedObjcClass.objcTypeName

        if swiftProperty.mutability == .mutable {
            writeLine("public var \(objcPropertyName): [\(objcClassName)]\(objcPropertyOptionality) {")
            indentRight()
                writeLine("set { root.swiftModel.\(propertyWrapper.keyPath) = newValue\(objcPropertyOptionality).map { $0.swiftModel } }")
                writeLine("get { root.swiftModel.\(propertyWrapper.keyPath)\(objcPropertyOptionality).map { \(objcClassName)(swiftModel: $0) } }")
            indentLeft()
            writeLine("}")
        } else {
            writeLine("public var \(objcPropertyName): [\(objcClassName)]\(objcPropertyOptionality) {")
            indentRight()
                writeLine("root.swiftModel.\(propertyWrapper.keyPath)\(objcPropertyOptionality).map { \(objcClassName)(swiftModel: $0) }")
            indentLeft()
            writeLine("}")
        }
    }

    private func printPrimitivePropertyWrapper(_ propertyWrapper: ObjcInteropPropertyWrapperManagingSwiftStructProperty) throws {
        let swiftProperty = propertyWrapper.bridgedSwiftProperty
        let objcPropertyName = swiftProperty.backtickName
        let objcPropertyOptionality = swiftProperty.isOptional ? "?" : ""
        let objcTypeName = try objcInteropTypeName(for: propertyWrapper.objcInteropType)
        let asObjcCast = try swiftToObjcCast(for: propertyWrapper.objcInteropType, isOptional: swiftProperty.isOptional) ?? ""

        if swiftProperty.mutability == .mutable {
            // Generate getter and setter for the managed value, e.g.:
            // ```
            // @objc public var propertyX: String? {
            //     set { root.swiftModel.bar.propertyX = newValue }
            //     get { root.swiftModel.bar.propertyX }
            // }
            // ```
            let toSwiftCast = try objcToSwiftCast(for: swiftProperty.type).ifNotNil { toSwiftCast in
                objcPropertyOptionality + toSwiftCast
            } ?? ""
            writeLine("public var \(objcPropertyName): \(objcTypeName)\(objcPropertyOptionality) {")
            indentRight()
                writeLine("set { root.swiftModel.\(propertyWrapper.keyPath) = newValue\(toSwiftCast) }")
                writeLine("get { root.swiftModel.\(propertyWrapper.keyPath)\(asObjcCast) }")
            indentLeft()
            writeLine("}")
        } else {
            // Generate getter for the managed value, e.g.:
            // ```
            // @objc public var propertyX: String? {
            //     root.swiftModel.bar.propertyX
            // }
            // ```
            writeLine("public var \(objcPropertyName): \(objcTypeName)\(objcPropertyOptionality) {")
            indentRight()
                writeLine("root.swiftModel.\(propertyWrapper.keyPath)\(asObjcCast)")
            indentLeft()
            writeLine("}")
        }
    }

    private func printPropertyAccessingNestedAssociatedTypeEnum(_ propertyWrapper: ObjcInteropPropertyWrapperAccessingNestedAssociatedTypeEnum) throws {
        let nestedObjcAssociatedTypeEnum = propertyWrapper.objcNestedAssociatedTypeEnum! // swiftlint:disable:this force_unwrapping

        // Generate accessor to the referenced wrapper, e.g.:
        // ```
        // @objc public var bar: DDFooBar? {
        //     root.swiftModel.bar != nil ? DDFooBar(root: root) : nil
        // }
        // ```
        let swiftProperty = propertyWrapper.bridgedSwiftProperty
        let objcPropertyName = swiftProperty.backtickName
        let objcPropertyOptionality = swiftProperty.isOptional ? "?" : ""
        let objcClassName = objcTypeNamesPrefix + nestedObjcAssociatedTypeEnum.objcTypeName
        writeLine("public var \(objcPropertyName): \(objcClassName)\(objcPropertyOptionality) {")
        indentRight()
            if swiftProperty.isOptional {
                // The property is optional, so the accessor must be returned only if the wrapped value is `!= nil`, e.g.:
                // ```
                // root.swiftModel.bar != nil ? DDFooBar(root: root) : nil
                // ```
                writeLine("root.swiftModel.\(propertyWrapper.keyPath) != nil ? \(objcClassName)(root: root) : nil")
            } else {
                // The property is non-optional, so accessor can be provided without considering `nil` value:
                // ```
                // DDFooBar(root: root)
                // ```
                writeLine("\(objcClassName)(root: root)")
            }
        indentLeft()
        writeLine("}")
    }

    // MARK: - Generating names

    private func objcInteropTypeName(for objcType: ObjcInteropType) throws -> String {
        switch objcType {
        case is ObjcInteropNSNumber:
            return "NSNumber"
        case is ObjcInteropNSString:
            return "String"
        case is ObjcInteropAny:
            return "Any"
        case let objcArray as ObjcInteropNSArray:
            return "[\(try objcInteropTypeName(for: objcArray.element))]"
        case let objcDictionary as ObjcInteropNSDictionary:
            return "[\(try objcInteropTypeName(for: objcDictionary.key)): \(try objcInteropTypeName(for: objcDictionary.value))]"
        default:
            throw Exception.unimplemented(
                "Cannot print `ObjcInteropType` name for \(type(of: objcType))."
            )
        }
    }

    private func swiftToObjcCast(for objcType: ObjcInteropType, isOptional: Bool) throws -> String? {
        let optionality = isOptional ? "?" : ""
        switch objcType {
        case is ObjcInteropNSNumber:
            return " as NSNumber" + optionality
        case let nsArray as ObjcInteropNSArray where nsArray.element is ObjcInteropNSNumber:
            return " as [NSNumber]" + optionality
        case let nsDictionary as ObjcInteropNSDictionary where nsDictionary.value is ObjcInteropNSNumber:
            return " as [\(try objcInteropTypeName(for: nsDictionary.key)): NSNumber]" + optionality
        case is ObjcInteropNSString:
            return nil // `String` <> `NSString` interoperability doesn't require casting
        case let nsArray as ObjcInteropNSArray where nsArray.element is ObjcInteropNSString:
            return nil // `[String]` <> `[NSString]` interoperability doesn't require casting
        case let nsDictionary as ObjcInteropNSDictionary where nsDictionary.value is ObjcInteropNSString:
            return nil // `[Key: String]` <> `[Key: NSString]` interoperability doesn't require casting
        case let nsDictionary as ObjcInteropNSDictionary where nsDictionary.value is ObjcInteropAny:
            // Normally, `[Key: Any]` <> `[Key: Any]` interoperability wouldn't require casting.
            // However our SDK bridges `[String: Any]` attributes passed in Objective-C API to their `[String: Encodable]` representation
            // in underlying Swift SDK. This is done with `AnyEncodable` type erasure. To return these attributes back
            // to the user, `AnyEncodable` must be unpacked to its original `Any` value. This is done in `.dd.objCAttributes` extension
            // defined in `DatadogInternal` module. Here we just emit its invocation:
            return optionality + ".dd.objCAttributes"
        default:
            throw Exception.unimplemented("Cannot print `swiftToObjcCast()` for \(type(of: objcType)).")
        }
    }

    private func objcToSwiftCast(for swiftType: SwiftType) throws -> String? {
        switch swiftType {
        case is SwiftPrimitive<Bool>:
            return ".boolValue"
        case is SwiftPrimitive<Double>:
            return ".doubleValue"
        case is SwiftPrimitive<Int>:
            return ".intValue"
        case is SwiftPrimitive<Int64>:
            return ".int64Value"
        case let swiftArray as SwiftArray where swiftArray.element is SwiftPrimitive<String>:
            return nil // `[String]` <> `[NSString]` interoperability doesn't require casting
        case let swiftArray as SwiftArray where swiftArray.element is SwiftPrimitiveNoObjcInteropType:
            return nil
        case let swiftDictionary as SwiftDictionary where swiftDictionary.value is SwiftPrimitive<String>:
            return nil // `[Key: String]` <> `[Key: NSString]` interoperability doesn't require casting
        case let swiftDictionary as SwiftDictionary where swiftDictionary.value is SwiftPrimitiveNoObjcInteropType:
            return ".dd.swiftAttributes"
        case let swiftArray as SwiftArray:
            let elementCast = try objcToSwiftCast(for: swiftArray.element)
                .unwrapOrThrow(.illegal("Cannot print `objcToSwiftCast()` for `SwiftArray` with elements of type: \(type(of: swiftArray.element))"))
            return ".map { $0\(elementCast) }"
        case let swiftDictionary as SwiftDictionary:
            let keyCast = try objcToSwiftCast(for: swiftDictionary.key) ?? ""
            let valueCast = try objcToSwiftCast(for: swiftDictionary.value)
                .unwrapOrThrow(.illegal("Cannot print `objcToSwiftCast()` for `SwiftDictionary` with values of type: \(type(of: swiftDictionary.value))"))
            return ".reduce(into: [:]) { $0[$1.0\(keyCast)] = $1.1\(valueCast) }"
        case is SwiftPrimitive<String>:
            return nil // `String` <> `NSString` interoperability doesn't require casting
        default:
            throw Exception.unimplemented("Cannot print `objcToSwiftCast()` for \(type(of: swiftType)).")
        }
    }
}

private extension String {
    var objcNaming: String {
        let objcPrefix = "objc_"
        if self.hasPrefix(objcPrefix) {
            return "DD" + self.dropFirst(objcPrefix.count)
        }
        return self
    }
}
