/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import RUMModelsGeneratorCore

final class RUMSwiftTypeTransformerTests: XCTestCase {
    func testTransformingUsingRUMNamesAndConventions() throws {
        let `struct` = SwiftStruct(
            name: "FooBar",
            comment: "Description of FooBar.",
            properties: [
                SwiftStruct.Property(
                    name: "bar",
                    comment: "Description of Bar.",
                    type: SwiftStruct(
                        name: "bar",
                        comment: "Description of Bar.",
                        properties: [
                            SwiftStruct.Property(
                                name: "property1",
                                comment: "Description of Bar's `property1`.",
                                type: SwiftPrimitive<String>(),
                                isOptional: true,
                                isMutable: false,
                                defaultValue: nil,
                                codingKey: .static(value: "property1")
                            ),
                            SwiftStruct.Property(
                                name: "property2",
                                comment: "Description of Bar's `property2`.",
                                type: SwiftPrimitive<String>(),
                                isOptional: false,
                                isMutable: true,
                                defaultValue: nil,
                                codingKey: .static(value: "property2")
                            )
                        ],
                        conformance: []
                    ),
                    isOptional: true,
                    isMutable: false,
                    defaultValue: nil,
                    codingKey: .static(value: "bar")
                ),
                SwiftStruct.Property(
                    name: "property1",
                    comment: "Description of FooBar's `property1`.",
                    type: SwiftEnum(
                        name: "property1",
                        comment: "Description of FooBar's `property1`.",
                        cases: [
                            SwiftEnum.Case(label: "case 1", rawValue: .string(value: "case 1")),
                            SwiftEnum.Case(label: "case 2", rawValue: .string(value: "case 2")),
                            SwiftEnum.Case(label: "case 3", rawValue: .string(value: "case 3")),
                            SwiftEnum.Case(label: "case 4", rawValue: .string(value: "case 4")),
                        ],
                        conformance: []
                    ),
                    isOptional: false,
                    isMutable: false,
                    defaultValue: SwiftEnum.Case(label: "case2", rawValue: .string(value: "case2")),
                    codingKey: .static(value: "property1")
                ),
                SwiftStruct.Property(
                    name: "property2",
                    comment: "Description of FooBar's `property2`.",
                    type: SwiftArray(
                        element: SwiftEnum(
                            name: "property2",
                            comment: nil,
                            cases: [
                                SwiftEnum.Case(label: "option-1", rawValue: .string(value: "option-1")),
                                SwiftEnum.Case(label: "option-2", rawValue: .string(value: "option-2")),
                                SwiftEnum.Case(label: "option-3", rawValue: .string(value: "option-3")),
                                SwiftEnum.Case(label: "option-4", rawValue: .string(value: "option-4")),
                            ],
                            conformance: []
                        )
                    ),
                    isOptional: true,
                    isMutable: true,
                    defaultValue: nil,
                    codingKey: .static(value: "property2")
                ),
                SwiftStruct.Property(
                    name: "propertiesByNames",
                    comment: "Description of Foobar's `propertiesByNames`",
                    type: SwiftDictionary(value: SwiftPrimitive<Int>()),
                    isOptional: true,
                    isMutable: true,
                    defaultValue: nil,
                    codingKey: .static(value: "propertiesByNames")
                )
            ],
            conformance: []
        )

        let actual = try RUMSwiftTypeTransformer().transform(types: [`struct`])

        let expected = [
            SwiftStruct(
                name: "FooBar",
                comment: "Description of FooBar.",
                properties: [
                    SwiftStruct.Property(
                        name: "bar",
                        comment: "Description of Bar.",
                        type: SwiftStruct(
                            name: "BAR",
                            comment: "Description of Bar.",
                            properties: [
                                SwiftStruct.Property(
                                    name: "property1",
                                    comment: "Description of Bar's `property1`.",
                                    type: SwiftPrimitive<String>(),
                                    isOptional: true,
                                    isMutable: false,
                                    defaultValue: nil,
                                    codingKey: .static(value: "property1")
                                ),
                                SwiftStruct.Property(
                                    name: "property2",
                                    comment: "Description of Bar's `property2`.",
                                    type: SwiftPrimitive<String>(),
                                    isOptional: false,
                                    isMutable: true,
                                    defaultValue: nil,
                                    codingKey: .static(value: "property2")
                                )
                            ],
                            conformance: [codableProtocol]
                        ),
                        isOptional: true,
                        isMutable: false,
                        defaultValue: nil,
                        codingKey: .static(value: "bar")
                    ),
                    SwiftStruct.Property(
                        name: "property1",
                        comment: "Description of FooBar's `property1`.",
                        type: SwiftEnum(
                            name: "Property1",
                            comment: "Description of FooBar's `property1`.",
                            cases: [
                                SwiftEnum.Case(label: "case1", rawValue: .string(value: "case 1")),
                                SwiftEnum.Case(label: "case2", rawValue: .string(value: "case 2")),
                                SwiftEnum.Case(label: "case3", rawValue: .string(value: "case 3")),
                                SwiftEnum.Case(label: "case4", rawValue: .string(value: "case 4")),
                            ],
                            conformance: [codableProtocol]
                        ),
                        isOptional: false,
                        isMutable: false,
                        defaultValue: SwiftEnum.Case(label: "case2", rawValue: .string(value: "case2")),
                        codingKey: .static(value: "property1")
                    ),
                    SwiftStruct.Property(
                        name: "property2",
                        comment: "Description of FooBar's `property2`.",
                        type: SwiftArray(
                            element: SwiftEnum(
                                name: "Property2",
                                comment: nil,
                                cases: [
                                    SwiftEnum.Case(label: "option1", rawValue: .string(value: "option-1")),
                                    SwiftEnum.Case(label: "option2", rawValue: .string(value: "option-2")),
                                    SwiftEnum.Case(label: "option3", rawValue: .string(value: "option-3")),
                                    SwiftEnum.Case(label: "option4", rawValue: .string(value: "option-4")),
                                ],
                                conformance: [codableProtocol]
                            )
                        ),
                        isOptional: true,
                        isMutable: true,
                        defaultValue: nil,
                        codingKey: .static(value: "property2")
                    ),
                    SwiftStruct.Property(
                        name: "propertiesByNames",
                        comment: "Description of Foobar's `propertiesByNames`",
                        type: SwiftDictionary(value: SwiftPrimitive<Int64>()),
                        isOptional: true,
                        isMutable: true,
                        defaultValue: nil,
                        codingKey: .static(value: "propertiesByNames")
                    )
                ],
                conformance: [SwiftProtocol(name: "RUMDataModel", conformance: [codableProtocol])]
            )
        ]

        XCTAssertEqual(expected, try XCTUnwrap(actual as? [SwiftStruct]))
    }

    func testTransformingSharedTypes() throws {
        let `struct` = SwiftStruct(
            name: "FooBar",
            comment: nil,
            properties: [
                SwiftStruct.Property(
                    name: "connectivity",
                    comment: nil,
                    type: SwiftStruct(
                        name: "connectivity",
                        comment: nil,
                        properties: [],
                        conformance: []
                    ),
                    isOptional: true,
                    isMutable: false,
                    defaultValue: nil,
                    codingKey: .static(value: "connectivity")
                ),
                SwiftStruct.Property(
                    name: "usr",
                    comment: nil,
                    type: SwiftStruct(
                        name: "usr",
                        comment: nil,
                        properties: [],
                        conformance: []
                    ),
                    isOptional: true,
                    isMutable: false,
                    defaultValue: nil,
                    codingKey: .static(value: "usr")
                ),
                SwiftStruct.Property(
                    name: "method",
                    comment: nil,
                    type: SwiftEnum(
                        name: "method",
                        comment: nil,
                        cases: [],
                        conformance: []
                    ),
                    isOptional: true,
                    isMutable: false,
                    defaultValue: nil,
                    codingKey: .static(value: "method")
                )
            ],
            conformance: []
        )

        let actual = try RUMSwiftTypeTransformer().transform(types: [`struct`])

        let expected: [SwiftType] = [
            SwiftStruct(
                name: "FooBar",
                comment: nil,
                properties: [
                    SwiftStruct.Property(
                        name: "connectivity",
                        comment: nil,
                        type: SwiftTypeReference(referencedTypeName: "RUMConnectivity"),
                        isOptional: true,
                        isMutable: false,
                        defaultValue: nil,
                        codingKey: .static(value: "connectivity")
                    ),
                    SwiftStruct.Property(
                        name: "usr",
                        comment: nil,
                        type: SwiftTypeReference(referencedTypeName: "RUMUser"),
                        isOptional: true,
                        isMutable: false,
                        defaultValue: nil,
                        codingKey: .static(value: "usr")
                    ),
                    SwiftStruct.Property(
                        name: "method",
                        comment: nil,
                        type: SwiftTypeReference(referencedTypeName: "RUMMethod"),
                        isOptional: true,
                        isMutable: false,
                        defaultValue: nil,
                        codingKey: .static(value: "method")
                    )
                ],
                conformance: [SwiftProtocol(name: "RUMDataModel", conformance: [codableProtocol])]
            ),
            SwiftStruct(
                name: "RUMConnectivity",
                comment: nil,
                properties: [],
                conformance: [codableProtocol]
            ),
            SwiftStruct(
                name: "RUMUser",
                comment: nil,
                properties: [],
                conformance: [codableProtocol]
            ),
            SwiftEnum(
                name: "RUMMethod",
                comment: nil,
                cases: [],
                conformance: [codableProtocol]
            )
        ]

        XCTAssertEqual(expected, actual)
    }
}
