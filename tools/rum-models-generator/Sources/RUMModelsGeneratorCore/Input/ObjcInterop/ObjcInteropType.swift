/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import Foundation

/// Type-safe Swift ↔ Objc interopability schema.
internal protocol ObjcInteropType: AnyObject {}

/// An interop class which manages Swift `struct`.
internal protocol ObjcInteropClass: ObjcInteropType {
    var managedSwiftStruct: SwiftStruct { get }
    var objcPropertyWrappers: [ObjcInteropPropertyWrapper] { set get }
}

/// Schema a root `@objc class` storing the mutable value of a `SwiftStruct`.
internal class ObjcInteropRootClass: ObjcInteropClass {
    /// The `SwiftStruct` managed by this `@objc class`.
    let managedSwiftStruct: SwiftStruct
    /// `managedSwiftStruct's` property wrappers exposed to Objc.
    var objcPropertyWrappers: [ObjcInteropPropertyWrapper] = []

    init(managedSwiftStruct: SwiftStruct) {
        self.managedSwiftStruct = managedSwiftStruct
    }
}

/// Schema of an `@objc class` managing the access to a nested `SwiftStruct`.
internal class ObjcInteropTransitiveClass: ObjcInteropClass {
    /// Property wrapper in the parent class, which stores the definition of this transitive class.
    private(set) unowned var parentProperty: ObjcInteropPropertyWrapper

    /// The nested `SwiftStruct` managed by this `@objc class`.
    let managedSwiftStruct: SwiftStruct
    /// `managedSwiftStruct's` property wrappers exposed to Objc.
    var objcPropertyWrappers: [ObjcInteropPropertyWrapper] = []

    init(owner: ObjcInteropPropertyWrapper, managedSwiftStruct: SwiftStruct) {
        self.parentProperty = owner
        self.managedSwiftStruct = managedSwiftStruct
    }
}

/// Schema of an `@objc class` managing the access to a nested `SwiftStruct` referenced using `SwiftTypeReference`.
internal class ObjcInteropReferencedTransitiveClass: ObjcInteropTransitiveClass {}

/// Schema of an `@objc enum` exposing values of a `SwiftEnum`.
internal class ObjcInteropEnum: ObjcInteropType {
    /// Property wrapper in the parent class, which stores the definition of this `ObjcInteropEnum`.
    private(set) unowned var parentProperty: ObjcInteropPropertyWrapper
    /// The `SwiftEnum` wrapped by this Obj-c enum.
    let managedSwiftEnum: SwiftEnum

    init(owner: ObjcInteropPropertyWrapper, managedSwiftEnum: SwiftEnum) {
        self.parentProperty = owner
        self.managedSwiftEnum = managedSwiftEnum
    }
}

/// Schema of an `@objc enum` exposing values a `SwiftEnum` referenced using `SwiftTypeReference`.
internal class ObjcInteropReferencedEnum: ObjcInteropEnum {}

/// Schema of an `@objc enum` exposing values from an array of `SwiftEnums`.
internal class ObjcInteropEnumArray: ObjcInteropEnum {}

// MARK: - Property wrapper schemas

/// Schema fo an `@objc` property which manages the access to a `SwiftStruct` property.
internal class ObjcInteropPropertyWrapper: ObjcInteropType {
    /// The class owning this property.
    private(set) unowned var owner: ObjcInteropClass
    /// Corresponding Swift property in `SwiftStruct`.
    let swiftProperty: SwiftStruct.Property

    init(owner: ObjcInteropClass, swiftProperty: SwiftStruct.Property) {
        self.owner = owner
        self.swiftProperty = swiftProperty
    }
}

/// A property wrapper which uses another `ObjcInteropType` for managing the acces to nested `SwiftStruct` property.
internal protocol ObjcInteropPropertyWrapperForTransitiveType {
    var objcTransitiveType: ObjcInteropType { get }
}

/// Schema for an `@objc` property managing the access to nested `SwiftStruct`.
internal class ObjcInteropPropertyWrapperAccessingNestedStruct: ObjcInteropPropertyWrapper, ObjcInteropPropertyWrapperForTransitiveType {
    var objcNestedClass: ObjcInteropTransitiveClass! // swiftlint:disable:this implicitly_unwrapped_optional
    var objcTransitiveType: ObjcInteropType { objcNestedClass }
}

/// Schema for an `@objc` property managing the access to nested `SwiftEnum`.
internal class ObjcInteropPropertyWrapperAccessingNestedEnum: ObjcInteropPropertyWrapper, ObjcInteropPropertyWrapperForTransitiveType {
    var objcNestedEnum: ObjcInteropEnum! // swiftlint:disable:this implicitly_unwrapped_optional
    var objcTransitiveType: ObjcInteropType { objcNestedEnum }
}

/// Schema for an `@objc` property managing the access array of `SwiftEnums`.
internal class ObjcInteropPropertyWrapperAccessingNestedEnumsArray: ObjcInteropPropertyWrapper, ObjcInteropPropertyWrapperForTransitiveType {
    var objcNestedEnumsArray: ObjcInteropEnumArray! // swiftlint:disable:this implicitly_unwrapped_optional
    var objcTransitiveType: ObjcInteropType { objcNestedEnumsArray }
}

/// Schema for an `@objc` property managing the access to `SwiftStruct` property.
internal class ObjcInteropPropertyWrapperManagingSwiftStructProperty: ObjcInteropPropertyWrapper {
    var objcInteropType: ObjcInteropType! // swiftlint:disable:this implicitly_unwrapped_optional
}

// MARK: - Plaing type schemas

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

internal class ObjcInteropNSArray: ObjcInteropType {
    let element: ObjcInteropType

    init(element: ObjcInteropType) {
        self.element = element
    }
}
