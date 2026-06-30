/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import CodeGeneration
@testable import CodeDecoration

final class SRCodeDecoratorTests: XCTestCase {
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
                )
            ],
            conformance: []
        )
    }

    private static func compositeOperation(named name: String) -> SwiftEnum {
        SwiftEnum(name: name, comment: nil, cases: [], conformance: [])
    }
}
