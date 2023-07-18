/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import CodeGeneration

/// Adjusts naming and structure of generated code for Session Replay.
public class SRCodeDecorator: SwiftCodeDecorator {
    /// `SRDataModel` protocol, implemented by all Session Replay models.
    private let srDataModelProtocol = SwiftProtocol(name: "SRDataModel", conformance: [codableProtocol])
    /// `Hashable` protocol, implemented by wireframes which need to be compared in diff (for incremental records).
    private let hashableProtocol = SwiftProtocol(name: "Hashable", conformance: [codableProtocol])

    public init() {
        super.init(
            sharedTypeNames: [
                // For convenience, make wireframes to be root types:
                "SRShapeWireframe",
                "SRTextWireframe",
                "SRImageWireframe",
                "SRPlaceholderWireframe",
                // For convenience, make fat `*Record` structures to be root types:
                "SRFullSnapshotRecord",
                "SRIncrementalSnapshotRecord",
                "SRMetaRecord",
                "SRFocusRecord",
                "SRViewEndRecord",
                "SRVisualViewportRecord",
                // For convenience, detach `SRMobileSegment.Record` to root-level `SRRecord`:
                "SRRecord",
                // For convenience, detach `SRMobileFullSnapshotRecord.Data.Wireframes`
                // and `SRMobileIncrementalSnapshotRecord.Update.Add.Wireframes` to root-level `SRWireframe`:
                "SRWireframe",
                // For convenience, detach styles from each wireframe to shared, root-level definition:
                "SRShapeBorder",
                "SRContentClip",
                "SRShapeStyle",
                "SRTextPosition",
                "SRTextStyle",
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

        let isWireframe = `struct`.name.lowercased().contains("wireframe")
        let isNestedInWireframe = context.predecessorStruct(matching: { $0.name.lowercased().contains("wireframe") }) != nil
        let notWireframeUpdate = !`struct`.name.hasSuffix("WireframeUpdate") // to exclude `TextWireframeUpdate`, `ShapeWireframeUpdate`, ...

        if (isWireframe || isNestedInWireframe) && notWireframeUpdate {
            `struct`.conformance.append(hashableProtocol)
        }

        return `struct`
    }

    override public func format(structName: String) -> String {
        super.format(
            structName: structName
                .replacingOccurrences(of: "mobile", with: "")
                .replacingOccurrences(of: "Mobile", with: "") // erase "[M|m]obile" in names
        )
    }

    override public func format(enumCaseName: String) -> String {
        super.format(
            enumCaseName: enumCaseName
                .replacingOccurrences(of: "mobile", with: "")
                .replacingOccurrences(of: "Mobile", with: "") // erase "[M|m]obile" in names
        )
    }

    // MARK: - Naming Conventions

    override public func fix(typeName: String) -> String {
        var fixedName = super.fix(typeName: typeName)

        // If the type name uses an abbreviation, keep it uppercased:
        if fixedName.count <= 3 {
            fixedName = typeName.uppercased()
        }

        // Basic renamings:
        if fixedName == "Records" {
            fixedName = "SRRecord"
        }
        if fixedName == "Wireframes" {
            fixedName = "SRWireframe"
        }

        // Detach styles from each wireframe to shared, root-level definitions
        let parentWireframe = context.predecessorStruct(matching: { $0.name.lowercased().contains("wireframe") })
        if parentWireframe != nil && fixedName == "Border" {
            fixedName = "SRShapeBorder"
        }
        if parentWireframe != nil && fixedName == "Clip" {
            fixedName = "SRContentClip"
        }
        if parentWireframe != nil && fixedName == "ShapeStyle" {
            fixedName = "SRShapeStyle"
        }
        if parentWireframe != nil && fixedName == "TextPosition" {
            fixedName = "SRTextPosition"
        }
        if parentWireframe != nil && fixedName == "TextStyle" {
            fixedName = "SRTextStyle"
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

private extension TransformationContext {
    func predecessorStruct(matching predicate: (SwiftStruct) -> Bool) -> SwiftStruct? {
        return predecessor(matching: {
            guard let `struct` = $0 as? SwiftStruct else {
                return false
            }
            return predicate(`struct`)
        }) as? SwiftStruct
    }
}
