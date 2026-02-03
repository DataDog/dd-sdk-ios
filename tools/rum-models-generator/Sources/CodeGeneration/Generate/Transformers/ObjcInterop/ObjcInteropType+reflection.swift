/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation

// MARK: - Reflection Helpers

// swiftlint:disable force_cast

internal protocol ObjcInteropReflectable {
    var objcRootClass: ObjcInteropRootClass { get }
    var objcTypeName: String { get }
    var swiftTypeName: String { get }
}

extension ObjcInteropRootClass: ObjcInteropReflectable {
    var objcRootClass: ObjcInteropRootClass { self }
    var objcTypeName: String { bridgedSwiftStruct.name }
    var swiftTypeName: String { bridgedSwiftStruct.name }
}

extension ObjcInteropTransitiveNestedClass: ObjcInteropReflectable {
    private var parentClass: ObjcInteropClass {
        return parentProperty.owner
    }

    var objcRootClass: ObjcInteropRootClass {
        return (parentClass as! ObjcInteropReflectable).objcRootClass
    }

    var objcTypeName: String {
        return (parentClass as! ObjcInteropReflectable).objcTypeName + bridgedSwiftStruct.name
    }

    var swiftTypeName: String {
        if self is ObjcInteropReferencedTransitiveClass {
            return bridgedSwiftStruct.name
        }
        return (parentClass as! ObjcInteropReflectable).swiftTypeName + "." + bridgedSwiftStruct.name
    }
}

extension ObjcInteropNestedClass: ObjcInteropReflectable {
    private var parentClass: ObjcInteropClass {
        return parentProperty.owner
    }

    var objcRootClass: ObjcInteropRootClass {
        return (parentClass as! ObjcInteropReflectable).objcRootClass
    }

    var objcTypeName: String {
        return (parentClass as! ObjcInteropReflectable).objcTypeName + bridgedSwiftStruct.name
    }

    var swiftTypeName: String {
        return (parentClass as! ObjcInteropReflectable).swiftTypeName + "." + bridgedSwiftStruct.name
    }
}

extension ObjcInteropNestedEnum: ObjcInteropReflectable {
    private var parentClass: ObjcInteropClass {
        return parentProperty.owner
    }

    var objcRootClass: ObjcInteropRootClass {
        return (parentClass as! ObjcInteropReflectable).objcRootClass
    }

    var objcTypeName: String {
        return (parentClass as! ObjcInteropReflectable).objcTypeName + bridgedSwiftEnum.name
    }

    var swiftTypeName: String {
        if self is ObjcInteropReferencedEnum {
            return bridgedSwiftEnum.name
        }
        return (parentClass as! ObjcInteropReflectable).swiftTypeName + "." + bridgedSwiftEnum.name
    }
}

extension ObjcInteropAssociatedTypeEnum: ObjcInteropReflectable {
    private var parentClass: ObjcInteropClass {
        return parentProperty.owner
    }

    var objcRootClass: ObjcInteropRootClass {
        return (parentClass as! ObjcInteropReflectable).objcRootClass
    }

    var objcTypeName: String {
        return (parentClass as! ObjcInteropReflectable).objcTypeName + bridgedSwiftAssociatedTypeEnum.name
    }

    var swiftTypeName: String {
        return (parentClass as! ObjcInteropReflectable).swiftTypeName + "." + bridgedSwiftAssociatedTypeEnum.name
    }
}

extension ObjcInteropPropertyWrapper {
    /// A key-path referencing this property, e.g. if this property is called `property` and belongs to class `Bar`,
    /// stored on property named `bar` in class `Foo`, then the `keyPath` is `bar.property`.
    var keyPath: String {
        let swiftPropertyName = bridgedSwiftProperty.name

        if let parentNestedClass = owner as? ObjcInteropTransitiveNestedClass {
            let parentProperty = parentNestedClass.parentProperty
            let forceUnwrapping = parentProperty.bridgedSwiftProperty.isOptional ? "!" : ""
            return parentProperty.keyPath + forceUnwrapping + "." + swiftPropertyName
        } else {
            return swiftPropertyName
        }
    }
}

// swiftlint:enable force_cast
