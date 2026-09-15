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
    /// `Hashable` protocol, implemented by models which need to be compared in diff (for incremental records).
    private let hashableProtocol = SwiftProtocol(name: "Hashable", conformance: [codableProtocol])

    public init() {
        super.init(
            sharedTypeNames: [
                // For convenience, make wireframes to be root types:
                "SRShapeWireframe",
                "SRTextWireframe",
                "SRImageWireframe",
                "SRPlaceholderWireframe",
                "SRWebviewWireframe",
                "SREmbeddedContentWireframe",
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
                // Detach shape gradient types to shared, root-level definitions:
                "SRShapeGradient",
                "SRShapeLinearGradient",
                "SRShapeGradientPoint",
                "SRShapeGradientStop",
                // Detach composition tree types to shared, root-level definitions:
                "SRCompositionTree",
                "SRCompositionLayer",
                "SRCompositionLayerChild",
                "SRCompositionLayerChildType",
                "SRCompositionLayerModifier",
                "SRCompositionLayerClipModifier",
                "SRCompositionLayerOpacityModifier",
                "SRCompositionLayerColorMatrixModifier",
                "SRCompositionLayerGaussianBlurModifier",
                "SRCompositionLayerShadowModifier",
                "SRCompositionLayerBrightnessBiasModifier",
                "SRCompositionLayerSaturateModifier",
                "SRCompositionLayerMaskImageModifier",
                "SRCompositionLayerUpdate",
                "SRCompositionTreeMutationData",
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
        let isCompositionLayer = `struct`.name.lowercased().contains("compositionlayer")
        let notWireframeUpdate = !`struct`.name.hasSuffix("WireframeUpdate") // to exclude `TextWireframeUpdate`, `ShapeWireframeUpdate`, ...

        if ((isWireframe || isNestedInWireframe) && notWireframeUpdate) || isCompositionLayer {
            `struct`.conformance.append(hashableProtocol)
        }

        return `struct`
    }

    override public func transform(associatedTypeEnum: SwiftAssociatedTypeEnum) throws -> SwiftAssociatedTypeEnum {
        var transformed = try super.transform(associatedTypeEnum: associatedTypeEnum)

        if transformed.name == "SRWireframe" {
            transformed = addDiscriminator("type", to: transformed, basedOn: associatedTypeEnum)
        }

        if transformed.name == "Updates", canAddDiscriminator("type", to: associatedTypeEnum) {
            transformed = addDiscriminator("type", to: transformed, basedOn: associatedTypeEnum)
        }

        if transformed.name == "SRCompositionLayerModifier" {
            transformed = addDiscriminator("type", to: transformed, basedOn: associatedTypeEnum)
            transformed.conformance.append(hashableProtocol)
        }

        if transformed.name == "SRShapeGradient" {
            transformed = addDiscriminator("type", to: transformed, basedOn: associatedTypeEnum)
            transformed.conformance.append(hashableProtocol)
        }

        let parentIncrementalSnapshotRecord = context.predecessorStruct(
            matching: { $0.name.lowercased() == "mobileincrementalsnapshotrecord" }
        )
        if associatedTypeEnum.name.lowercased() == "data" && parentIncrementalSnapshotRecord != nil {
            transformed = addDiscriminator("source", to: transformed, basedOn: associatedTypeEnum)
        }

        return transformed
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
                .replacingOccurrences(of: "ShapeLinearGradient", with: "linear")
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

        // Detach shape gradient types to shared, root-level definitions.
        let parentShapeStyle = context.predecessorStruct(matching: { $0.name.lowercased() == "shapestyle" })
        let parentLinearGradient = context.predecessorStruct(matching: { $0.name.lowercased() == "shapelineargradient" })
        if parentShapeStyle != nil && fixedName == "BackgroundGradient" {
            fixedName = "SRShapeGradient"
        }
        if parentLinearGradient != nil && (fixedName == "EndPoint" || fixedName == "StartPoint") {
            fixedName = "SRShapeGradientPoint"
        }
        if parentLinearGradient != nil && fixedName == "Stops" {
            fixedName = "SRShapeGradientStop"
        }

        // Detach composition tree types to shared, root-level definitions.
        let parentCompositionTree = context.predecessorStruct(matching: { $0.name.lowercased() == "compositiontree" })
        let parentCompositionTreeMutationData = context.predecessorStruct(
            matching: { $0.name.lowercased() == "compositiontreemutationdata" }
        )
        let isNestedInCompositionTree = parentCompositionTree != nil || parentCompositionTreeMutationData != nil

        if parentCompositionTree != nil && (fixedName == "Layers" || fixedName == "Root") {
            fixedName = "SRCompositionLayer"
        }
        if parentCompositionTreeMutationData != nil && (fixedName == "Adds" || fixedName == "Root") {
            fixedName = "SRCompositionLayer"
        }
        if parentCompositionTreeMutationData != nil && fixedName == "Updates" {
            fixedName = "SRCompositionLayerUpdate"
        }
        if isNestedInCompositionTree && fixedName == "Children" {
            fixedName = "SRCompositionLayerChild"
        }
        if isNestedInCompositionTree && fixedName == "ChildrenType" {
            fixedName = "SRCompositionLayerChildType"
        }
        if isNestedInCompositionTree && fixedName == "Modifiers" {
            fixedName = "SRCompositionLayerModifier"
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

    private func addDiscriminator(
        _ codingKey: String,
        to associatedTypeEnum: SwiftAssociatedTypeEnum,
        basedOn originalAssociatedTypeEnum: SwiftAssociatedTypeEnum
    ) -> SwiftAssociatedTypeEnum {
        var associatedTypeEnum = associatedTypeEnum
        associatedTypeEnum.discriminatorCodingKey = codingKey
        // `super.transform` keeps case order while renaming cases and associated types.
        // Keep this in mind if the base transformer starts reordering cases.
        associatedTypeEnum.cases = zip(originalAssociatedTypeEnum.cases, associatedTypeEnum.cases).map { originalCase, transformedCase in
            var transformedCase = transformedCase
            transformedCase.discriminatorValue = discriminatorValue(for: codingKey, in: originalCase.associatedType)
            if codingKey == "source", let value = transformedCase.discriminatorValue as? Int {
                transformedCase.discriminatorValue = Int64(value)
            }
            return transformedCase
        }
        return associatedTypeEnum
    }

    private func discriminatorValue(for codingKey: String, in swiftType: SwiftType) -> SwiftPropertyDefaultValue? {
        guard let `struct` = swiftType as? SwiftStruct else {
            return nil
        }
        return `struct`.properties.first {
            guard case .static(let value) = $0.codingKey else {
                return false
            }
            return value == codingKey
        }?.defaultValue
    }

    private func canAddDiscriminator(_ codingKey: String, to associatedTypeEnum: SwiftAssociatedTypeEnum) -> Bool {
        !associatedTypeEnum.cases.isEmpty && associatedTypeEnum.cases.allSatisfy {
            discriminatorValue(for: codingKey, in: $0.associatedType) != nil
        }
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
