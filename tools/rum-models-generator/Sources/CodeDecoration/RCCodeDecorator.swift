/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CodeGeneration

/// Adjusts naming and structure of generated code for Remote Configuration.
public class RCCodeDecorator: SwiftCodeDecorator {
    public override init(sharedTypeNames: [String] = []) {
        super.init(sharedTypeNames: sharedTypeNames)
    }

    // MARK: - Naming Conventions

    override public func format(enumCaseName: String) -> String {
        // $id-based variant names are hyphenated (e.g. "rum-sdk-config-ios").
        // Use only the last component as the case label ("ios").
        enumCaseName.contains("-") ? enumCaseName.components(separatedBy: "-").last ?? enumCaseName
                                   : super.format(enumCaseName: enumCaseName)
    }

    // MARK: - Types customisation

    override public func transform(primitive: SwiftPrimitiveType) -> SwiftPrimitiveType {
        if primitive is SwiftPrimitive<Int> {
            return SwiftPrimitive<Int64>() // Replace all `Int` with `Int64`
        }
        return super.transform(primitive: primitive)
    }

    // MARK: - Naming Conventions

    override public func fix(typeName: String) -> String {
        var fixedName = super.fix(typeName: typeName)

        // If the type name starts with "rum" (any-cased), keep it uppercased.
        if fixedName.lowercased().hasPrefix("rum") {
            fixedName = fixedName.prefix(3).uppercased() + fixedName.suffix(fixedName.count - 3)
        }

        return fixedName
    }
}
