/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import CodeGeneration

/// Adjusts naming and structure of generated code for RUM.
public class RUMCodeDecorator: SwiftCodeDecorator {
    /// `RUMDataModel` protocol, implemented by all RUM models.
    private let rumDataModelProtocol = SwiftProtocol(name: "RUMDataModel", conformance: [codableProtocol])

    public init() {
        super.init(
            sharedTypeNames: [
                "RUMConnectivity",
                "RUMUser",
                "RUMMethod",
                "RUMEventAttributes",
                "RUMCITest",
                "RUMDevice",
                "RUMOperatingSystem",
                "RUMActionID",
            ]
        )
    }

    // MARK: - Types customiation

    override public func transform(primitive: SwiftPrimitiveType) -> SwiftPrimitiveType {
        if primitive is SwiftPrimitive<Int> {
            return SwiftPrimitive<Int64>() // Replace all `Int` with `Int64`
        } else {
            return super.transform(primitive: primitive)
        }
    }

    override public func transform(struct: SwiftStruct) throws -> SwiftStruct {
        var `struct` = try super.transform(struct: `struct`)

        if context.parent == nil {
            `struct`.conformance = [rumDataModelProtocol] // Conform root structs to `RUMDataModel`
        }

        return `struct`
    }

    // MARK: - Naming Conventions

    override public func format(enumCaseName: String) -> String {
        // When generating enum cases for Resource's HTTP method, force lowercase
        // (`.get`, `.post`, ...)
        if (context.current as? SwiftEnum)?.name.lowercased() == "method" {
            return enumCaseName.lowercased()
        }

        return super.format(enumCaseName: enumCaseName)
    }

    override public func fix(typeName: String) -> String {
        var fixedName = super.fix(typeName: typeName)

        // If the type name uses an abbreviation, keep it uppercased.
        if fixedName.count <= 3 {
            fixedName = typeName.uppercased()
        }

        // If the name starts with "rum" (any-cased), ensure it gets uppercased.
        if fixedName.lowercased().hasPrefix("rum") {
            fixedName = fixedName.prefix(3).uppercased() + fixedName.suffix(fixedName.count - 3)
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

        // Since https://github.com/DataDog/rum-events-format/pull/57 `action.id` can be either
        // single `String` or an array of `[String]`. This is handled by generating Swift enum with
        // two cases and different associated types. To not duplicate generated code in each nested
        // context we generate single root type: `RUMActionID`.
        if fixedName == "ID", let parentStructName = (context.parent as? SwiftStruct)?.name, parentStructName == "action" {
            fixedName = "RUMActionID"
        }

        return fixedName
    }
}
