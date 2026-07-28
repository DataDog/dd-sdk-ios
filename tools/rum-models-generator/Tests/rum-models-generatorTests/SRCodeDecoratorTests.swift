/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import CodeGeneration
@testable import CodeDecoration

final class SRCodeDecoratorTests: XCTestCase {
    func testDecoratingWireframeSharedTypesAndDiscriminator() throws {
        let wireframe = SwiftAssociatedTypeEnum(
            name: "Wireframes",
            comment: nil,
            cases: [
                SwiftAssociatedTypeEnum.Case(
                    label: "ShapeWireframe",
                    associatedType: Self.shapeWireframe(named: "ShapeWireframe")
                ),
                SwiftAssociatedTypeEnum.Case(
                    label: "EmbeddedContentWireframe",
                    associatedType: Self.embeddedContentWireframe(named: "EmbeddedContentWireframe")
                )
            ],
            conformance: []
        )

        let actual = try SRCodeDecorator()
            .decorate(code: GeneratedCode(swiftTypes: [wireframe]))

        let typeNames = actual.swiftTypes.compactMap(\.typeName)
        XCTAssertTrue(typeNames.contains("SRShapeWireframe"))
        XCTAssertTrue(typeNames.contains("SREmbeddedContentWireframe"))
        XCTAssertFalse(typeNames.contains("EmbeddedContentWireframe"))

        let transformedWireframe = try XCTUnwrap(actual.swiftTypes.first { $0.typeName == "SRWireframe" } as? SwiftAssociatedTypeEnum)
        XCTAssertEqual("type", transformedWireframe.discriminatorCodingKey)
        XCTAssertEqual("shape", transformedWireframe.cases.first?.discriminatorValue as? String)
        XCTAssertEqual("embedded_content", transformedWireframe.cases.dropFirst().first?.discriminatorValue as? String)
        XCTAssertEqual(
            "SREmbeddedContentWireframe",
            (transformedWireframe.cases.dropFirst().first?.associatedType as? SwiftTypeReference)?.referencedTypeName
        )
    }

    func testDecoratingWireframeUpdateMutationDiscriminator() throws {
        let incrementalSnapshotRecord = SwiftStruct(
            name: "MobileIncrementalSnapshotRecord",
            comment: nil,
            properties: [
                Self.property(
                    named: "data",
                    type: SwiftAssociatedTypeEnum(
                        name: "data",
                        comment: nil,
                        cases: [
                            SwiftAssociatedTypeEnum.Case(
                                label: "MutationData",
                                associatedType: SwiftStruct(
                                    name: "WireframeMutationData",
                                    comment: nil,
                                    properties: [
                                        Self.property(
                                            named: "source",
                                            type: SwiftPrimitive<Int>(),
                                            defaultValue: 2
                                        ),
                                        Self.property(
                                            named: "updates",
                                            type: SwiftArray(
                                                element: SwiftAssociatedTypeEnum(
                                                    name: "updates",
                                                    comment: nil,
                                                    cases: [
                                                        SwiftAssociatedTypeEnum.Case(
                                                            label: "WebviewWireframeUpdate",
                                                            associatedType: Self.webviewWireframeUpdate()
                                                        ),
                                                        SwiftAssociatedTypeEnum.Case(
                                                            label: "EmbeddedContentWireframeUpdate",
                                                            associatedType: Self.embeddedContentWireframeUpdate()
                                                        )
                                                    ],
                                                    conformance: []
                                                )
                                            )
                                        )
                                    ],
                                    conformance: []
                                )
                            )
                        ],
                        conformance: []
                    )
                )
            ],
            conformance: []
        )

        let actual = try SRCodeDecorator()
            .decorate(code: GeneratedCode(swiftTypes: [incrementalSnapshotRecord]))

        let record = try XCTUnwrap(actual.swiftTypes.first { $0.typeName == "SRIncrementalSnapshotRecord" } as? SwiftStruct)
        let data = try XCTUnwrap(record.properties.first { $0.name == "data" }?.type as? SwiftAssociatedTypeEnum)
        let mutationData = try XCTUnwrap(data.cases.first?.associatedType as? SwiftStruct)
        let updates = try XCTUnwrap(
            (mutationData.properties.first { $0.name == "updates" }?.type as? SwiftArray)?.element as? SwiftAssociatedTypeEnum
        )

        XCTAssertEqual("type", updates.discriminatorCodingKey)
        XCTAssertEqual("webview", updates.cases.first?.discriminatorValue as? String)
        XCTAssertEqual("embedded_content", updates.cases.dropFirst().first?.discriminatorValue as? String)
    }

    func testDecoratingShapeGradientSharedTypes() throws {
        let shapeWireframe = SwiftStruct(
            name: "ShapeWireframe",
            comment: nil,
            properties: [
                Self.property(
                    named: "shapeStyle",
                    type: SwiftStruct(
                        name: "shapeStyle",
                        comment: nil,
                        properties: [
                            Self.property(
                                named: "backgroundGradient",
                                type: Self.shapeGradient(named: "backgroundGradient"),
                                isOptional: true
                            )
                        ],
                        conformance: []
                    )
                )
            ],
            conformance: []
        )

        let actual = try SRCodeDecorator()
            .decorate(code: GeneratedCode(swiftTypes: [shapeWireframe]))

        let typeNames = actual.swiftTypes.compactMap(\.typeName)
        XCTAssertTrue(typeNames.contains("SRShapeStyle"))
        XCTAssertTrue(typeNames.contains("SRShapeGradient"))
        XCTAssertTrue(typeNames.contains("SRShapeLinearGradient"))
        XCTAssertTrue(typeNames.contains("SRShapeGradientPoint"))
        XCTAssertTrue(typeNames.contains("SRShapeGradientStop"))
        XCTAssertFalse(typeNames.contains("BackgroundGradient"))
        XCTAssertFalse(typeNames.contains("EndPoint"))
        XCTAssertFalse(typeNames.contains("StartPoint"))
        XCTAssertFalse(typeNames.contains("Stops"))

        let shapeStyle = try XCTUnwrap(actual.swiftTypes.first { $0.typeName == "SRShapeStyle" } as? SwiftStruct)
        let backgroundGradient = try XCTUnwrap(shapeStyle.properties.first { $0.name == "backgroundGradient" })
        XCTAssertEqual("SRShapeGradient", (backgroundGradient.type as? SwiftTypeReference)?.referencedTypeName)

        let shapeGradient = try XCTUnwrap(
            actual.swiftTypes.first { $0.typeName == "SRShapeGradient" } as? SwiftAssociatedTypeEnum
        )
        XCTAssertEqual("type", shapeGradient.discriminatorCodingKey)
        XCTAssertEqual("linear", shapeGradient.cases.first?.label)
        XCTAssertEqual("linear", shapeGradient.cases.first?.discriminatorValue as? String)
        XCTAssertEqual(
            "SRShapeLinearGradient",
            (shapeGradient.cases.first?.associatedType as? SwiftTypeReference)?.referencedTypeName
        )
        XCTAssertTrue(shapeGradient.conforms(to: hashableProtocol))

        let linearGradient = try XCTUnwrap(
            actual.swiftTypes.first { $0.typeName == "SRShapeLinearGradient" } as? SwiftStruct
        )
        let startPoint = try XCTUnwrap(linearGradient.properties.first { $0.name == "startPoint" })
        let endPoint = try XCTUnwrap(linearGradient.properties.first { $0.name == "endPoint" })
        let stops = try XCTUnwrap(linearGradient.properties.first { $0.name == "stops" })
        XCTAssertEqual("SRShapeGradientPoint", (startPoint.type as? SwiftTypeReference)?.referencedTypeName)
        XCTAssertEqual("SRShapeGradientPoint", (endPoint.type as? SwiftTypeReference)?.referencedTypeName)
        XCTAssertEqual(
            "SRShapeGradientStop",
            ((stops.type as? SwiftArray)?.element as? SwiftTypeReference)?.referencedTypeName
        )
        XCTAssertTrue(linearGradient.conforms(to: hashableProtocol))

        let point = try XCTUnwrap(actual.swiftTypes.first { $0.typeName == "SRShapeGradientPoint" } as? SwiftStruct)
        XCTAssertTrue(point.conforms(to: hashableProtocol))

        let stop = try XCTUnwrap(actual.swiftTypes.first { $0.typeName == "SRShapeGradientStop" } as? SwiftStruct)
        XCTAssertTrue(stop.conforms(to: hashableProtocol))
    }

    func testDecoratingCompositionTreeSharedTypes() throws {
        let fullSnapshotRecord = SwiftStruct(
            name: "MobileFullSnapshotRecord",
            comment: nil,
            properties: [
                Self.property(
                    named: "data",
                    type: SwiftStruct(
                        name: "data",
                        comment: nil,
                        properties: [
                            Self.property(
                                named: "compositionTree",
                                type: SwiftStruct(
                                    name: "compositionTree",
                                    comment: nil,
                                    properties: [
                                        Self.property(
                                            named: "layers",
                                            type: SwiftArray(element: Self.compositionLayer(named: "layers")),
                                            isOptional: true
                                        ),
                                        Self.property(named: "root", type: Self.compositionLayer(named: "root"))
                                    ],
                                    conformance: []
                                ),
                                isOptional: true
                            )
                        ],
                        conformance: []
                    )
                )
            ],
            conformance: []
        )
        let incrementalSnapshotRecord = SwiftStruct(
            name: "MobileIncrementalSnapshotRecord",
            comment: nil,
            properties: [
                Self.property(
                    named: "data",
                    type: SwiftAssociatedTypeEnum(
                        name: "data",
                        comment: nil,
                        cases: [
                            SwiftAssociatedTypeEnum.Case(
                                label: "CompositionTreeMutationData",
                                associatedType: SwiftStruct(
                                    name: "CompositionTreeMutationData",
                                    comment: nil,
                                    properties: [
                                        Self.property(
                                            named: "adds",
                                            type: SwiftArray(element: Self.compositionLayer(named: "adds")),
                                            isOptional: true
                                        ),
                                        Self.property(named: "root", type: Self.compositionLayer(named: "root"), isOptional: true),
                                        Self.property(
                                            named: "source",
                                            type: SwiftPrimitive<Int>(),
                                            defaultValue: 10
                                        ),
                                        Self.property(
                                            named: "updates",
                                            type: SwiftArray(element: Self.compositionLayerUpdate(named: "updates")),
                                            isOptional: true
                                        )
                                    ],
                                    conformance: []
                                )
                            )
                        ],
                        conformance: []
                    )
                )
            ],
            conformance: []
        )

        let actual = try SRCodeDecorator()
            .decorate(code: GeneratedCode(swiftTypes: [fullSnapshotRecord, incrementalSnapshotRecord]))

        let typeNames = actual.swiftTypes.compactMap { $0.typeName }
        XCTAssertTrue(typeNames.contains("SRCompositionTree"))
        XCTAssertTrue(typeNames.contains("SRCompositionLayer"))
        XCTAssertTrue(typeNames.contains("SRCompositionLayerChild"))
        XCTAssertTrue(typeNames.contains("SRCompositionLayerModifier"))
        XCTAssertTrue(typeNames.contains("SRCompositionLayerShadowModifier"))
        XCTAssertTrue(typeNames.contains("SRCompositionLayerMaskImageModifier"))
        XCTAssertTrue(typeNames.contains("SRCompositionLayerUpdate"))
        XCTAssertTrue(typeNames.contains("SRCompositionTreeMutationData"))
        XCTAssertFalse(typeNames.contains("Layers"))
        XCTAssertFalse(typeNames.contains("Root"))
        XCTAssertFalse(typeNames.contains("Adds"))
        XCTAssertFalse(typeNames.contains("Updates"))

        let compositionTree = try XCTUnwrap(actual.swiftTypes.first { $0.typeName == "SRCompositionTree" } as? SwiftStruct)
        let layers: SwiftStruct.Property = try XCTUnwrap(compositionTree.properties.first { $0.name == "layers" })
        XCTAssertEqual("SRCompositionLayer", ((layers.type as? SwiftArray)?.element as? SwiftTypeReference)?.referencedTypeName)

        let root: SwiftStruct.Property = try XCTUnwrap(compositionTree.properties.first { $0.name == "root" })
        XCTAssertEqual("SRCompositionLayer", (root.type as? SwiftTypeReference)?.referencedTypeName)

        let mutationData = try XCTUnwrap(actual.swiftTypes.first { $0.typeName == "SRCompositionTreeMutationData" } as? SwiftStruct)
        let adds: SwiftStruct.Property = try XCTUnwrap(mutationData.properties.first { $0.name == "adds" })
        XCTAssertEqual("SRCompositionLayer", ((adds.type as? SwiftArray)?.element as? SwiftTypeReference)?.referencedTypeName)

        let mutationRoot: SwiftStruct.Property = try XCTUnwrap(mutationData.properties.first { $0.name == "root" })
        XCTAssertEqual("SRCompositionLayer", (mutationRoot.type as? SwiftTypeReference)?.referencedTypeName)

        let updates: SwiftStruct.Property = try XCTUnwrap(mutationData.properties.first { $0.name == "updates" })
        XCTAssertEqual("SRCompositionLayerUpdate", ((updates.type as? SwiftArray)?.element as? SwiftTypeReference)?.referencedTypeName)

        let compositionLayer = try XCTUnwrap(actual.swiftTypes.first { $0.typeName == "SRCompositionLayer" } as? SwiftStruct)
        XCTAssertTrue(compositionLayer.conforms(to: hashableProtocol))

        let compositionLayerChild = try XCTUnwrap(actual.swiftTypes.first { $0.typeName == "SRCompositionLayerChild" } as? SwiftStruct)
        XCTAssertTrue(compositionLayerChild.conforms(to: hashableProtocol))

        let compositionLayerUpdate = try XCTUnwrap(actual.swiftTypes.first { $0.typeName == "SRCompositionLayerUpdate" } as? SwiftStruct)
        XCTAssertTrue(compositionLayerUpdate.conforms(to: hashableProtocol))

        let transformedIncrementalSnapshotRecord = try XCTUnwrap(
            actual.swiftTypes.first { $0.typeName == "SRIncrementalSnapshotRecord" } as? SwiftStruct
        )
        let incrementalData = try XCTUnwrap(
            transformedIncrementalSnapshotRecord.properties.first { $0.name == "data" }?.type as? SwiftAssociatedTypeEnum
        )
        XCTAssertEqual("source", incrementalData.discriminatorCodingKey)
        XCTAssertEqual(Int64(10), incrementalData.cases.first?.discriminatorValue as? Int64)

        let modifier = try XCTUnwrap(actual.swiftTypes.first { $0.typeName == "SRCompositionLayerModifier" } as? SwiftAssociatedTypeEnum)
        XCTAssertEqual("type", modifier.discriminatorCodingKey)
        XCTAssertEqual("clip", modifier.cases.first?.discriminatorValue as? String)
        XCTAssertEqual("shadow", modifier.cases.dropFirst().first?.discriminatorValue as? String)
        XCTAssertEqual("maskImage", modifier.cases.dropFirst(2).first?.discriminatorValue as? String)
        XCTAssertTrue(modifier.conforms(to: hashableProtocol))
    }

    private let hashableProtocol = SwiftProtocol(name: "Hashable", conformance: [codableProtocol])

    private static func property(
        named name: String,
        type: SwiftType,
        isOptional: Bool = false,
        defaultValue: SwiftPropertyDefaultValue? = nil
    ) -> SwiftStruct.Property {
        SwiftStruct.Property(
            name: name,
            comment: nil,
            type: type,
            isOptional: isOptional,
            mutability: .immutable,
            defaultValue: defaultValue,
            codingKey: .static(value: name)
        )
    }

    private static func shapeWireframe(named name: String) -> SwiftStruct {
        SwiftStruct(
            name: name,
            comment: nil,
            properties: [
                property(named: "id", type: SwiftPrimitive<Int>()),
                property(named: "type", type: SwiftPrimitive<String>(), defaultValue: "shape")
            ],
            conformance: []
        )
    }

    private static func embeddedContentWireframe(named name: String) -> SwiftStruct {
        SwiftStruct(
            name: name,
            comment: nil,
            properties: [
                property(named: "id", type: SwiftPrimitive<Int>()),
                property(named: "slotId", type: SwiftPrimitive<String>()),
                property(named: "type", type: SwiftPrimitive<String>(), defaultValue: "embedded_content")
            ],
            conformance: []
        )
    }

    private static func webviewWireframeUpdate() -> SwiftStruct {
        SwiftStruct(
            name: "WebviewWireframeUpdate",
            comment: nil,
            properties: [
                property(named: "id", type: SwiftPrimitive<Int>()),
                property(named: "slotId", type: SwiftPrimitive<String>()),
                property(named: "type", type: SwiftPrimitive<String>(), defaultValue: "webview")
            ],
            conformance: []
        )
    }

    private static func embeddedContentWireframeUpdate() -> SwiftStruct {
        SwiftStruct(
            name: "EmbeddedContentWireframeUpdate",
            comment: nil,
            properties: [
                property(named: "id", type: SwiftPrimitive<Int>()),
                property(named: "slotId", type: SwiftPrimitive<String>()),
                property(named: "type", type: SwiftPrimitive<String>(), defaultValue: "embedded_content")
            ],
            conformance: []
        )
    }

    private static func compositionLayer(named name: String) -> SwiftStruct {
        SwiftStruct(
            name: name,
            comment: nil,
            properties: [
                property(named: "children", type: SwiftArray(element: compositionLayerChild(named: "children"))),
                property(named: "compositeOperation", type: compositeOperation(named: "compositeOperation"), isOptional: true),
                property(named: "modifiers", type: SwiftArray(element: compositionLayerModifier(named: "modifiers")), isOptional: true)
            ],
            conformance: []
        )
    }

    private static func shapeGradient(named name: String) -> SwiftAssociatedTypeEnum {
        SwiftAssociatedTypeEnum(
            name: name,
            comment: nil,
            cases: [
                SwiftAssociatedTypeEnum.Case(
                    label: "ShapeLinearGradient",
                    associatedType: SwiftStruct(
                        name: "ShapeLinearGradient",
                        comment: nil,
                        properties: [
                            property(named: "endPoint", type: shapeGradientPoint(named: "endPoint")),
                            property(named: "startPoint", type: shapeGradientPoint(named: "startPoint")),
                            property(
                                named: "stops",
                                type: SwiftArray(element: shapeGradientStop(named: "stops"))
                            ),
                            property(
                                named: "type",
                                type: SwiftPrimitive<String>(),
                                defaultValue: "linear"
                            )
                        ],
                        conformance: []
                    )
                )
            ],
            conformance: []
        )
    }

    private static func shapeGradientPoint(named name: String) -> SwiftStruct {
        SwiftStruct(
            name: name,
            comment: nil,
            properties: [
                property(named: "x", type: SwiftPrimitive<Double>()),
                property(named: "y", type: SwiftPrimitive<Double>())
            ],
            conformance: []
        )
    }

    private static func shapeGradientStop(named name: String) -> SwiftStruct {
        SwiftStruct(
            name: name,
            comment: nil,
            properties: [
                property(named: "color", type: SwiftPrimitive<String>()),
                property(named: "position", type: SwiftPrimitive<Double>())
            ],
            conformance: []
        )
    }

    private static func compositionLayerUpdate(named name: String) -> SwiftStruct {
        SwiftStruct(
            name: name,
            comment: nil,
            properties: [
                property(named: "children", type: SwiftArray(element: compositionLayerChild(named: "children")), isOptional: true),
                property(named: "compositeOperation", type: compositeOperation(named: "compositeOperation"), isOptional: true),
                property(named: "modifiers", type: SwiftArray(element: compositionLayerModifier(named: "modifiers")), isOptional: true)
            ],
            conformance: []
        )
    }

    private static func compositionLayerChild(named name: String) -> SwiftStruct {
        SwiftStruct(
            name: name,
            comment: nil,
            properties: [
                property(named: "type", type: SwiftEnum(name: "type", comment: nil, cases: [], conformance: []))
            ],
            conformance: []
        )
    }

    private static func compositionLayerModifier(named name: String) -> SwiftAssociatedTypeEnum {
        SwiftAssociatedTypeEnum(
            name: name,
            comment: nil,
            cases: [
                SwiftAssociatedTypeEnum.Case(
                    label: "CompositionLayerClipModifier",
                    associatedType: SwiftStruct(
                        name: "CompositionLayerClipModifier",
                        comment: nil,
                        properties: [
                            property(
                                named: "type",
                                type: SwiftPrimitive<String>(),
                                defaultValue: "clip"
                            )
                        ],
                        conformance: []
                    )
                ),
                SwiftAssociatedTypeEnum.Case(
                    label: "CompositionLayerShadowModifier",
                    associatedType: SwiftStruct(
                        name: "CompositionLayerShadowModifier",
                        comment: nil,
                        properties: [
                            property(
                                named: "type",
                                type: SwiftPrimitive<String>(),
                                defaultValue: "shadow"
                            )
                        ],
                        conformance: []
                    )
                ),
                SwiftAssociatedTypeEnum.Case(
                    label: "CompositionLayerMaskImageModifier",
                    associatedType: SwiftStruct(
                        name: "CompositionLayerMaskImageModifier",
                        comment: nil,
                        properties: [
                            property(
                                named: "type",
                                type: SwiftPrimitive<String>(),
                                defaultValue: "maskImage"
                            )
                        ],
                        conformance: []
                    )
                )
            ],
            conformance: []
        )
    }

    private static func compositeOperation(named name: String) -> SwiftEnum {
        SwiftEnum(name: name, comment: nil, cases: [], conformance: [])
    }
}
