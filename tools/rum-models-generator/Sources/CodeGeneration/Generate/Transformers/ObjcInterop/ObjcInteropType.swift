/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

// MARK: - Type wrapper schemas

/// Type-safe Swift ↔ Objc interoperability schema.
internal protocol ObjcInteropType: AnyObject {}

/// Any `@objc class` which manages Swift `struct`.
internal protocol ObjcInteropClass: ObjcInteropType {
    /// The Swift struct that this Objective-C class wraps and provides interoperability for.
    /// This class acts as a bridge, exposing the struct's properties to Objective-C code.
    var bridgedSwiftStruct: SwiftStruct { get }
    /// Array of property wrappers that generate Objective-C accessors for each property in `bridgedSwiftStruct`.
    /// One wrapper per Swift property - each knows how to generate getter/setter code and handle type conversion between Swift and Objective-C.
    var objcPropertyWrappers: [ObjcInteropPropertyWrapper] { set get }
}

/// Schema of a root `@objc class` storing the mutable value of a `SwiftStruct`.
internal class ObjcInteropRootClass: ObjcInteropClass {
    /// The `SwiftStruct` managed by this `@objc class`.
    let bridgedSwiftStruct: SwiftStruct
    /// `bridgedSwiftStruct's` property wrappers exposed to Objc.
    var objcPropertyWrappers: [ObjcInteropPropertyWrapper] = []

    init(bridgedSwiftStruct: SwiftStruct) {
        self.bridgedSwiftStruct = bridgedSwiftStruct
    }
}

/// Schema of a transitive `@objc class` managing the access to the nested `SwiftStruct`.
internal class ObjcInteropTransitiveNestedClass: ObjcInteropClass {
    /// Property wrapper in the parent class, which stores the definition of this transitive class.
    private(set) unowned var parentProperty: ObjcInteropPropertyWrapper

    /// The nested `SwiftStruct` managed by this `@objc class`.
    let bridgedSwiftStruct: SwiftStruct
    /// `bridgedSwiftStruct's` property wrappers exposed to Objc.
    var objcPropertyWrappers: [ObjcInteropPropertyWrapper] = []

    init(owner: ObjcInteropPropertyWrapper, bridgedSwiftStruct: SwiftStruct) {
        self.parentProperty = owner
        self.bridgedSwiftStruct = bridgedSwiftStruct
    }
}

/// Schema of a transitive `@objc class` managing the access to a nested `SwiftStruct` referenced using `SwiftTypeReference`.
internal class ObjcInteropReferencedTransitiveClass: ObjcInteropTransitiveNestedClass {}

/// Schema of a non-transitive `@objc class` exposing values of nested `SwiftStruct`.
internal class ObjcInteropNestedClass: ObjcInteropClass {
    /// Property wrapper in the parent class, which stores the definition of this transitive class.
    unowned var parentProperty: ObjcInteropPropertyWrapper! // swiftlint:disable:this implicitly_unwrapped_optional

    /// The `SwiftStruct` managed by this `@objc class`.
    let bridgedSwiftStruct: SwiftStruct
    /// `bridgedSwiftStruct's` property wrappers exposed to Objc.
    var objcPropertyWrappers: [ObjcInteropPropertyWrapper] = []

    init(owner: ObjcInteropPropertyWrapper?, bridgedSwiftStruct: SwiftStruct) {
        self.parentProperty = owner
        self.bridgedSwiftStruct = bridgedSwiftStruct
    }
}

/// Schema of a transitive `@objc class` managing the access to a`SwiftEnum`.
internal class ObjcInteropEnum: ObjcInteropType {
    /// The `SwiftEnum` exposed by this Obj-c enum.
    let bridgedSwiftEnum: SwiftEnum

    init(bridgedSwiftEnum: SwiftEnum) {
        self.bridgedSwiftEnum = bridgedSwiftEnum
    }
}

/// Schema of an `@objc enum` exposing values for the `SwiftEnum`.
internal class ObjcInteropNestedEnum: ObjcInteropEnum {
    /// Property wrapper in the parent class, which stores the definition of this enum.
    private(set) unowned var parentProperty: ObjcInteropPropertyWrapper

    init(owner: ObjcInteropPropertyWrapper, bridgedSwiftEnum: SwiftEnum) {
        self.parentProperty = owner
        super.init(bridgedSwiftEnum: bridgedSwiftEnum)
    }
}

/// Schema of an `@objc enum` exposing values of the `SwiftEnum` referenced using `SwiftTypeReference`.
internal class ObjcInteropReferencedEnum: ObjcInteropNestedEnum {}

/// Schema of an `@objc enum` exposing values of an array of `SwiftEnums`.
internal class ObjcInteropEnumArray: ObjcInteropNestedEnum {}

/// Schema of an `@objc class` managing `SwiftAssociatedTypeEnum`.
internal class ObjcInteropAssociatedTypeEnum: ObjcInteropType {
    /// Property wrapper in the parent class, which stores the definition of this enum.
    private(set) unowned var parentProperty: ObjcInteropPropertyWrapper
    /// The `SwiftAssociatedTypeEnum` managed by this `@objc class`.
    let bridgedSwiftAssociatedTypeEnum: SwiftAssociatedTypeEnum
    /// An array of Objc-interop types for associated values in each case (follows the order of enum cases in `bridgedSwiftAssociatedTypeEnum`).
    var associatedObjcInteropTypes: [ObjcInteropType]

    init(
        owner: ObjcInteropPropertyWrapper,
        bridgedSwiftAssociatedTypeEnum: SwiftAssociatedTypeEnum,
        associatedObjcInteropTypes: [ObjcInteropType] = []
    ) {
        self.parentProperty = owner
        self.bridgedSwiftAssociatedTypeEnum = bridgedSwiftAssociatedTypeEnum
        self.associatedObjcInteropTypes = associatedObjcInteropTypes
    }
}

/// Schema of an `@objc class` managing `SwiftAssociatedTypeEnum` referenced using `SwiftTypeReference`.
internal class ObjcInteropReferencedAssociatedTypeEnum: ObjcInteropAssociatedTypeEnum {}

// MARK: - Property wrapper schemas

/// Schema for an `@objc` property which manages the access to the `SwiftStruct's` property.
internal class ObjcInteropPropertyWrapper: ObjcInteropType {
    /// The `@objc class` owning this property.
    private(set) unowned var owner: ObjcInteropClass
    /// Corresponding Swift property in `SwiftStruct`.
    let bridgedSwiftProperty: SwiftStruct.Property

    init(owner: ObjcInteropClass, swiftProperty: SwiftStruct.Property) {
        self.owner = owner
        self.bridgedSwiftProperty = swiftProperty
    }
}

/// A property wrapper which uses another `ObjcInteropType` for managing access to a property in nested `SwiftStruct`.
internal protocol ObjcInteropPropertyWrapperForTransitiveType {
    var objcTransitiveType: ObjcInteropType { get }
}

/// Schema of an `@objc` property managing access to the nested `SwiftStruct`.
internal class ObjcInteropPropertyWrapperAccessingNestedStruct: ObjcInteropPropertyWrapper, ObjcInteropPropertyWrapperForTransitiveType {
    var objcNestedClass: ObjcInteropTransitiveNestedClass! // swiftlint:disable:this implicitly_unwrapped_optional
    var objcTransitiveType: ObjcInteropType { objcNestedClass }
}

/// Schema of an `@objc` property managing access to the nested `SwiftEnum`.
internal class ObjcInteropPropertyWrapperAccessingNestedEnum: ObjcInteropPropertyWrapper, ObjcInteropPropertyWrapperForTransitiveType {
    var objcNestedEnum: ObjcInteropNestedEnum! // swiftlint:disable:this implicitly_unwrapped_optional
    var objcTransitiveType: ObjcInteropType { objcNestedEnum }
}

/// Schema of an `@objc` property managing access to the array of `SwiftEnums`.
internal class ObjcInteropPropertyWrapperAccessingNestedEnumsArray: ObjcInteropPropertyWrapper, ObjcInteropPropertyWrapperForTransitiveType {
    var objcNestedEnumsArray: ObjcInteropEnumArray! // swiftlint:disable:this implicitly_unwrapped_optional
    var objcTransitiveType: ObjcInteropType { objcNestedEnumsArray }
}

/// Schema of an `@objc` property managing access to the array of `SwiftStructs`.
internal class ObjcInteropPropertyWrapperAccessingNestedStructsArray: ObjcInteropPropertyWrapper, ObjcInteropPropertyWrapperForTransitiveType {
    var objcNestedClass: ObjcInteropNestedClass! // swiftlint:disable:this implicitly_unwrapped_optional
    var objcTransitiveType: ObjcInteropType { objcNestedClass }
}

/// Schema of an `@objc` property managing access to a property of the `SwiftStruct`.
internal class ObjcInteropPropertyWrapperManagingSwiftStructProperty: ObjcInteropPropertyWrapper {
    var objcInteropType: ObjcInteropType! // swiftlint:disable:this implicitly_unwrapped_optional
}

/// Schema fo an `@objc` property which manages the access to `SwiftAssociatedTypeEnum`.
internal class ObjcInteropPropertyWrapperAccessingNestedAssociatedTypeEnum: ObjcInteropPropertyWrapper, ObjcInteropPropertyWrapperForTransitiveType {
    var objcNestedClass: ObjcInteropTransitiveNestedClass?
    var objcNestedAssociatedTypeEnum: ObjcInteropAssociatedTypeEnum! // swiftlint:disable:this implicitly_unwrapped_optional
    var objcTransitiveType: ObjcInteropType { objcNestedAssociatedTypeEnum }
}

/// Schema of an `@objc` property managing access to the array of `SwiftAssociatedTypeEnums`.
internal class ObjcInteropPropertyWrapperAccessingNestedAssociatedTypeEnumsArray: ObjcInteropPropertyWrapper, ObjcInteropPropertyWrapperForTransitiveType {
    var objcNestedClass: ObjcInteropNestedClass! // swiftlint:disable:this implicitly_unwrapped_optional
    var objcTransitiveType: ObjcInteropType { objcNestedClass }
}

// MARK: - Plain type schemas

internal class ObjcInteropNSNumber: ObjcInteropType {
    let swiftType: SwiftType

    init(swiftType: SwiftType) {
        self.swiftType = swiftType
    }
}

internal class ObjcInteropNSString: ObjcInteropType {
    let swiftString: SwiftPrimitive<String>

    init(swiftString: SwiftPrimitive<String>) {
        self.swiftString = swiftString
    }
}

internal class ObjcInteropAny: ObjcInteropType {
    let swiftType: SwiftPrimitiveNoObjcInteropType

    init(swiftType: SwiftPrimitiveNoObjcInteropType) {
        self.swiftType = swiftType
    }
}

internal class ObjcInteropNSArray: ObjcInteropType {
    let element: ObjcInteropType

    init(element: ObjcInteropType) {
        self.element = element
    }
}

internal class ObjcInteropNSDictionary: ObjcInteropType {
    let key: ObjcInteropType
    let value: ObjcInteropType

    init(key: ObjcInteropType, value: ObjcInteropType) {
        self.key = key
        self.value = value
    }
}
