/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import CodeGeneration

final class SwiftCodeDecoratorTests: XCTestCase {
    func testDecoratingWithSwiftNamingConventions() throws {
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
                                mutability: .immutable,
                                defaultValue: nil,
                                codingKey: .static(value: "property1")
                            ),
                            SwiftStruct.Property(
                                name: "property2",
                                comment: "Description of Bar's `property2`.",
                                type: SwiftPrimitive<String>(),
                                isOptional: false,
                                mutability: .mutable,
                                defaultValue: nil,
                                codingKey: .static(value: "property2")
                            )
                        ],
                        conformance: []
                    ),
                    isOptional: true,
                    mutability: .immutable,
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
                    mutability: .immutable,
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
                    mutability: .mutable,
                    defaultValue: nil,
                    codingKey: .static(value: "property2")
                ),
                SwiftStruct.Property(
                    name: "propertiesByNames",
                    comment: "Description of Foobar's `propertiesByNames`",
                    type: SwiftDictionary(value: SwiftPrimitive<Int>()),
                    isOptional: true,
                    mutability: .mutable,
                    defaultValue: nil,
                    codingKey: .static(value: "propertiesByNames")
                )
            ],
            conformance: []
        )

        let actual = try SwiftCodeDecorator()
            .decorate(code: GeneratedCode(swiftTypes: [`struct`]))

        let expected = [
            SwiftStruct(
                name: "FooBar",
                comment: "Description of FooBar.",
                properties: [
                    SwiftStruct.Property(
                        name: "bar",
                        comment: "Description of Bar.",
                        type: SwiftStruct(
                            name: "Bar",
                            comment: "Description of Bar.",
                            properties: [
                                SwiftStruct.Property(
                                    name: "property1",
                                    comment: "Description of Bar's `property1`.",
                                    type: SwiftPrimitive<String>(),
                                    isOptional: true,
                                    mutability: .immutable,
                                    defaultValue: nil,
                                    codingKey: .static(value: "property1")
                                ),
                                SwiftStruct.Property(
                                    name: "property2",
                                    comment: "Description of Bar's `property2`.",
                                    type: SwiftPrimitive<String>(),
                                    isOptional: false,
                                    mutability: .mutable,
                                    defaultValue: nil,
                                    codingKey: .static(value: "property2")
                                )
                            ],
                            conformance: [codableProtocol]
                        ),
                        isOptional: true,
                        mutability: .immutable,
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
                        mutability: .immutable,
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
                        mutability: .mutable,
                        defaultValue: nil,
                        codingKey: .static(value: "property2")
                    ),
                    SwiftStruct.Property(
                        name: "propertiesByNames",
                        comment: "Description of Foobar's `propertiesByNames`",
                        type: SwiftDictionary(value: SwiftPrimitive<Int>()),
                        isOptional: true,
                        mutability: .mutable,
                        defaultValue: nil,
                        codingKey: .static(value: "propertiesByNames")
                    )
                ],
                conformance: [codableProtocol]
            )
        ]

        XCTAssertEqual(expected, try XCTUnwrap(actual.swiftTypes as? [SwiftStruct]))
    }

    func testTransformingSharedTypes() throws {
        let `struct` = SwiftStruct(
            name: "FooBar",
            comment: nil,
            properties: [
                SwiftStruct.Property(
                    name: "commonStruct1",
                    comment: nil,
                    type: SwiftStruct(
                        name: "commonStruct1",
                        comment: nil,
                        properties: [],
                        conformance: []
                    ),
                    isOptional: true,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .static(value: "commonStruct1")
                ),
                SwiftStruct.Property(
                    name: "commonStruct2",
                    comment: nil,
                    type: SwiftStruct(
                        name: "commonStruct2",
                        comment: nil,
                        properties: [],
                        conformance: []
                    ),
                    isOptional: true,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .static(value: "commonStruct2")
                ),
                SwiftStruct.Property(
                    name: "commonEnum",
                    comment: nil,
                    type: SwiftEnum(
                        name: "commonEnum",
                        comment: nil,
                        cases: [],
                        conformance: []
                    ),
                    isOptional: true,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .static(value: "commonEnum")
                )
            ],
            conformance: []
        )

        let decorator = SwiftCodeDecorator(
            sharedTypeNames: [
                "CommonStruct1",
                "CommonStruct2",
                "CommonEnum",
            ]
        )
        let actual = try decorator.decorate(code: GeneratedCode(swiftTypes: [`struct`]))

        let expected: [SwiftType] = [
            SwiftStruct(
                name: "FooBar",
                comment: nil,
                properties: [
                    SwiftStruct.Property(
                        name: "commonStruct1",
                        comment: nil,
                        type: SwiftTypeReference(referencedTypeName: "CommonStruct1"),
                        isOptional: true,
                        mutability: .immutable,
                        defaultValue: nil,
                        codingKey: .static(value: "commonStruct1")
                    ),
                    SwiftStruct.Property(
                        name: "commonStruct2",
                        comment: nil,
                        type: SwiftTypeReference(referencedTypeName: "CommonStruct2"),
                        isOptional: true,
                        mutability: .immutable,
                        defaultValue: nil,
                        codingKey: .static(value: "commonStruct2")
                    ),
                    SwiftStruct.Property(
                        name: "commonEnum",
                        comment: nil,
                        type: SwiftTypeReference(referencedTypeName: "CommonEnum"),
                        isOptional: true,
                        mutability: .immutable,
                        defaultValue: nil,
                        codingKey: .static(value: "commonEnum")
                    )
                ],
                conformance: [codableProtocol]
            ),
            SwiftStruct(
                name: "CommonStruct1",
                comment: nil,
                properties: [],
                conformance: [codableProtocol]
            ),
            SwiftStruct(
                name: "CommonStruct2",
                comment: nil,
                properties: [],
                conformance: [codableProtocol]
            ),
            SwiftEnum(
                name: "CommonEnum",
                comment: nil,
                cases: [],
                conformance: [codableProtocol]
            )
        ]

        XCTAssertEqual(expected, actual.swiftTypes)
    }
}
