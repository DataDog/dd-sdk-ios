/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import CodeGeneration

/// Adjusts naming and structure of generated code for Session Replay.
public class SRCodeDecorator: SwiftCodeDecorator {
    /// `SRDataModel` protocol, implemented by all Session Replay models.
    private let srDataModelProtocol = SwiftProtocol(name: "SRDataModel", conformance: [codableProtocol])

    public init() {
        super.init(
            sharedTypeNames: [
                // For convenience, make wireframes to be root types:
                "SRShapeWireframe",
                "SRTextWireframe",
                // For convenience, make fat `*Record` structures to be root types:
                "SRMobileFullSnapshotRecord",
                "SRMobileIncrementalSnapshotRecord",
                "SRMetaRecord",
                "SRFocusRecord",
                "SRViewEndRecord",
                "SRVisualViewportRecord",
                // For convenience, detach `SRMobileSegment.Record` to root-level `SRRecord`:
                "SRRecord"
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
            `struct`.conformance = [srDataModelProtocol] // Conform root structs to `SRDataModel`
        }

        return `struct`
    }

    // MARK: - Naming Conventions

    override public func fix(typeName: String) -> String {
        var fixedName = super.fix(typeName: typeName)

        // If the type name uses an abbreviation, keep it uppercased:
        if fixedName.count <= 3 {
            fixedName = typeName.uppercased()
        }

        // Rename `enum Records` to `enum Record`
        if fixedName == "Records" {
            fixedName = "SRRecord"
        }

        // Ensure all root types have `SR` prefix:
        let isRootType = context.parent == nil
        if isRootType && fixedName.uppercased().hasPrefix("SR") == false {
            fixedName = "SR" + fixedName
        }

        // Ensure all shared (originally nested, but detached) types have `SR` prefix:
        if sharedTypeNames.contains("SR" + typeName) {
            fixedName = "SR" + typeName
        }

        return fixedName
    }
}
