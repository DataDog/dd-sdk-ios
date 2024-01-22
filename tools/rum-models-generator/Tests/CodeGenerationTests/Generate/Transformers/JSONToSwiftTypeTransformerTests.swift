/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
@testable import CodeGeneration

final class JSONToSwiftTypeTransformerTests: XCTestCase {
    func testTransformingJSONObjectIntoSwiftStruct() throws {
        let object = JSONObject(
            name: "Foo",
            comment: "Description of Foo.",
            properties: [
                JSONObject.Property(
                    name: "bar",
                    comment: "Description of Bar.",
                    type: JSONObject(
                        name: "bar",
                        comment: "Description of Bar.",
                        properties: [
                            JSONObject.Property(
                                name: "property1",
                                comment: "Description of Bar's `property1`.",
                                type: JSONPrimitive.string,
                                defaultValue: nil,
                                isRequired: false,
                                isReadOnly: true
                            ),
                            JSONObject.Property(
                                name: "property2",
                                comment: "Description of Bar's `property2`.",
                                type: JSONPrimitive.string,
                                defaultValue: nil,
                                isRequired: true,
                                isReadOnly: false
                            )
                        ]
                    ),
                    defaultValue: nil,
                    isRequired: false,
                    isReadOnly: true
                ),
                JSONObject.Property(
                    name: "property1",
                    comment: "Description of Foo's `property1`.",
                    type: JSONEnumeration(
                        name: "property1",
                        comment: "Description of Foo's `property1`.",
                        values: [.string(value: "case1"), .string(value: "case2"), .string(value: "case3"), .string(value: "case4")]
                    ),
                    defaultValue: JSONObject.Property.DefaultValue.string(value: "case2"),
                    isRequired: true,
                    isReadOnly: true
                ),
                JSONObject.Property(
                    name: "property2",
                    comment: "Description of Foo's `property2`.",
                    type: JSONArray(
                        element: JSONEnumeration(
                            name: "property2",
                            comment: nil,
                            values: [.string(value: "option1"), .string(value: "option2"), .string(value: "option3"), .string(value: "option4")]
                        )
                    ),
                    defaultValue: nil,
                    isRequired: false,
                    isReadOnly: false
                )
            ]
        )

        let expected = SwiftStruct(
            name: "Foo",
            comment: "Description of Foo.",
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
                    mutability: .mutable, // should be mutable as at least one of the `Bar's` properties is mutable
                    defaultValue: nil,
                    codingKey: .static(value: "bar")
                ),
                SwiftStruct.Property(
                    name: "property1",
                    comment: "Description of Foo's `property1`.",
                    type: SwiftEnum(
                        name: "property1",
                        comment: "Description of Foo's `property1`.",
                        cases: [
                            SwiftEnum.Case(label: "case1", rawValue: .string(value: "case1")),
                            SwiftEnum.Case(label: "case2", rawValue: .string(value: "case2")),
                            SwiftEnum.Case(label: "case3", rawValue: .string(value: "case3")),
                            SwiftEnum.Case(label: "case4", rawValue: .string(value: "case4")),
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
                    comment: "Description of Foo's `property2`.",
                    type: SwiftArray(
                        element: SwiftEnum(
                            name: "property2",
                            comment: nil,
                            cases: [
                                SwiftEnum.Case(label: "option1", rawValue: .string(value: "option1")),
                                SwiftEnum.Case(label: "option2", rawValue: .string(value: "option2")),
                                SwiftEnum.Case(label: "option3", rawValue: .string(value: "option3")),
                                SwiftEnum.Case(label: "option4", rawValue: .string(value: "option4")),
                            ],
                            conformance: []
                        )
                    ),
                    isOptional: true,
                    mutability: .mutable,
                    defaultValue: nil,
                    codingKey: .static(value: "property2")
                )
            ],
            conformance: []
        )

        let actual = try JSONToSwiftTypeTransformer().transform(jsonType: object)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(expected, actual[0])
    }

    func testTransformingJSONObjectWithStringEnumerationIntoSwiftStruct() throws {
        let object = JSONObject(
            name: "Container",
            comment: nil,
            properties: [
                JSONObject.Property(
                    name: "enumeration",
                    comment: nil,
                    type: JSONEnumeration(
                        name: "Foo",
                        comment: "Description of Foo",
                        values: [
                            .string(value: "case1"),
                            .string(value: "case2"),
                            .string(value: "3case"), // case name starting with number
                            .string(value: "4case"),
                        ]
                    ),
                    defaultValue: nil,
                    isRequired: false,
                    isReadOnly: false
                )
            ]
        )

        let expected = SwiftStruct(
            name: "Container",
            properties: [
                SwiftStruct.Property(
                    name: "enumeration",
                    type: SwiftEnum(
                        name: "Foo",
                        comment: "Description of Foo",
                        cases: [
                            SwiftEnum.Case(label: "case1", rawValue: .string(value: "case1")),
                            SwiftEnum.Case(label: "case2", rawValue: .string(value: "case2")),
                            SwiftEnum.Case(label: "Foo3case", rawValue: .string(value: "3case")),
                            SwiftEnum.Case(label: "Foo4case", rawValue: .string(value: "4case")),
                        ],
                        conformance: []
                    ),
                    isOptional: true,
                    mutability: .mutable,
                    codingKey: .static(value: "enumeration")
                )
            ],
            conformance: []
        )

        let actual = try JSONToSwiftTypeTransformer().transform(jsonType: object)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(expected, actual[0])
    }

    func testTransformingJSONObjectWithIntegerEnumerationIntoSwiftStruct() throws {
        let object = JSONObject(
            name: "Container",
            comment: nil,
            properties: [
                JSONObject.Property(
                    name: "enumeration",
                    comment: nil,
                    type: JSONEnumeration(
                        name: "Foo",
                        comment: "Description of Foo",
                        values: [
                            .integer(value: 1),
                            .integer(value: 2),
                            .integer(value: 3),
                        ]
                    ),
                    defaultValue: nil,
                    isRequired: false,
                    isReadOnly: false
                )
            ]
        )

        let expected = SwiftStruct(
            name: "Container",
            properties: [
                SwiftStruct.Property(
                    name: "enumeration",
                    type: SwiftEnum(
                        name: "Foo",
                        comment: "Description of Foo",
                        cases: [
                            SwiftEnum.Case(label: "Foo1", rawValue: .integer(value: 1)),
                            SwiftEnum.Case(label: "Foo2", rawValue: .integer(value: 2)),
                            SwiftEnum.Case(label: "Foo3", rawValue: .integer(value: 3)),
                        ],
                        conformance: []
                    ),
                    isOptional: true,
                    mutability: .mutable,
                    codingKey: .static(value: "enumeration")
                )
            ],
            conformance: []
        )

        let actual = try JSONToSwiftTypeTransformer().transform(jsonType: object)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(expected, actual[0])
    }

    // MARK: - Transforming `additionalProperties`

    func testTransformingNestedJSONObjectWithIntAdditionalPropertiesIntoSwiftDictionaryInsideRootStruct() throws {
        let object = JSONObject(
            name: "Foo",
            comment: "Description of Foo.",
            properties: [
                JSONObject.Property(
                    name: "propertyWithAdditionalIntProperties",
                    comment: "Description of a property with nested additional Int properties.",
                    type: JSONObject(
                        name: "propertyWithAdditionalIntProperties",
                        comment: "Description of a property with nested additional Int properties.",
                        properties: [],
                        additionalProperties:
                            JSONObject.AdditionalProperties(
                                comment: nil,
                                type: JSONPrimitive.integer,
                                isReadOnly: true
                            )
                    ),
                    defaultValue: nil,
                    isRequired: false,
                    isReadOnly: true
                )
            ]
        )

        let expected = SwiftStruct(
            name: "Foo",
            comment: "Description of Foo.",
            properties: [
                SwiftStruct.Property(
                    name: "propertyWithAdditionalIntProperties",
                    comment: "Description of a property with nested additional Int properties.",
                    type: SwiftDictionary(value: SwiftPrimitive<Int>()),
                    isOptional: true,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .static(value: "propertyWithAdditionalIntProperties")
                )
            ],
            conformance: []
        )

        let actual = try JSONToSwiftTypeTransformer().transform(jsonType: object)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(expected, actual[0])
    }

    func testTransformingNestedJSONObjectWithAnyAdditionalPropertiesIntoSwiftDictionaryInsideRootStruct() throws {
        let object = JSONObject(
            name: "Foo",
            comment: "Description of Foo.",
            properties: [
                JSONObject.Property(
                    name: "propertyWithAdditionalAnyProperties",
                    comment: "Description of a property with nested additional Any properties.",
                    type: JSONObject(
                        name: "propertyWithAdditionalAnyProperties",
                        comment: "Description of a property with nested additional Any properties.",
                        properties: [],
                        additionalProperties:
                            JSONObject.AdditionalProperties(
                                comment: nil,
                                type: JSONPrimitive.any,
                                isReadOnly: true
                            )
                    ),
                    defaultValue: nil,
                    isRequired: false,
                    isReadOnly: true
                )
            ]
        )

        let expected = SwiftStruct(
            name: "Foo",
            comment: "Description of Foo.",
            properties: [
                SwiftStruct.Property(
                    name: "propertyWithAdditionalAnyProperties",
                    comment: "Description of a property with nested additional Any properties.",
                    type: SwiftStruct(
                        name: "propertyWithAdditionalAnyProperties",
                        comment: "Description of a property with nested additional Any properties.",
                        properties: [
                            SwiftStruct.Property(
                                name: "propertyWithAdditionalAnyPropertiesInfo",
                                comment: nil,
                                type: SwiftDictionary(
                                    value: SwiftEncodable()
                                ),
                                isOptional: false,
                                mutability: .mutableInternally,
                                defaultValue: nil,
                                codingKey: .dynamic
                            )
                        ],
                        conformance: []
                    ),
                    isOptional: true,
                    mutability: .mutableInternally,
                    defaultValue: nil,
                    codingKey: .static(value: "propertyWithAdditionalAnyProperties")
                )
            ],
            conformance: []
        )

        let actual = try JSONToSwiftTypeTransformer().transform(jsonType: object)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(expected, actual[0])
    }

    func testTransformingNestedJSONObjectWithPropertiesAndAdditionalPropertiesIntoSwiftStruct() throws {
        let object = JSONObject(
            name: "Foo",
            comment: "Description of Foo.",
            properties: [
                JSONObject.Property(
                    name: "bar",
                    comment: "Description of Foo's `bar`.",
                    type: JSONObject(
                        name: "bar",
                        comment: "Description `bar`.",
                        properties: [
                            JSONObject.Property(
                                    name: "bazz",
                                    comment: "Description of Foo.bar's `bazz`.",
                                    type: JSONPrimitive.string,
                                    defaultValue: nil,
                                    isRequired: false,
                                    isReadOnly: true
                                )
                        ],
                        additionalProperties: JSONObject.AdditionalProperties(
                            comment: "Additional properties of `bar`.",
                            type: JSONPrimitive.any,
                            isReadOnly: true
                        )
                    ),
                    defaultValue: nil,
                    isRequired: false,
                    isReadOnly: true
                )
            ]
        )

        let expected = SwiftStruct(
            name: "Foo",
            comment: "Description of Foo.",
            properties: [
                SwiftStruct.Property(
                    name: "bar",
                    comment: "Description of Foo's `bar`.",
                    type: SwiftStruct(
                        name: "bar",
                        comment: "Description `bar`.",
                        properties: [
                            SwiftStruct.Property(
                                name: "bazz",
                                comment: "Description of Foo.bar's `bazz`.",
                                type: SwiftPrimitive<String>(),
                                isOptional: true,
                                mutability: .immutable,
                                defaultValue: nil,
                                codingKey: .static(value: "bazz")
                            ),
                            SwiftStruct.Property(
                                name: "barInfo",
                                comment: "Additional properties of `bar`.",
                                type: SwiftDictionary(
                                    value: SwiftEncodable()
                                ),
                                isOptional: false,
                                mutability: .mutableInternally,
                                defaultValue: nil,
                                codingKey: .dynamic
                            ),
                        ],
                        conformance: []
                    ),
                    isOptional: true,
                    mutability: .mutableInternally,
                    defaultValue: nil,
                    codingKey: .static(value: "bar")
                )
            ],
            conformance: []
        )

        let actual = try JSONToSwiftTypeTransformer().transform(jsonType: object)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(expected, actual[0])
    }

    func testTransformingRootJSONObjectWithAdditionalPropertiesIntoSwiftStruct() throws {
        let object = JSONObject(
            name: "Foo",
            comment: "Description of Foo.",
            properties: [
                JSONObject.Property(
                    name: "bar",
                    comment: nil,
                    type: JSONPrimitive.string,
                    defaultValue: nil,
                    isRequired: false,
                    isReadOnly: true
                )
            ],
            additionalProperties: JSONObject.AdditionalProperties(
                comment: "Additional properties of Foo.",
                type: JSONPrimitive.string,
                isReadOnly: true
            )
        )

        XCTAssertThrowsError(try JSONToSwiftTypeTransformer().transform(jsonType: object)) { error in
            let exceptionDescription = (error as? Exception)?.description ?? ""
            XCTAssertTrue(
                exceptionDescription.contains("Transforming root `JSONObject`")
                && exceptionDescription.contains("is not supported")
            )
        }
    }

    func testTransformingJSONObjectPropertyWithAdditionalPropertiesAndConflictingFlags() throws {
        let object = JSONObject(
            name: "Foo",
            comment: "Description of Foo.",
            properties: [
                JSONObject.Property(
                    name: "propertyWithAdditionalProperties",
                    comment: "Description of a property with nested additional properties.",
                    type: JSONObject(
                        name: "propertyWithAdditionalProperties",
                        comment: "Description of a property with nested additional properties.",
                        properties: [],
                        additionalProperties:
                            JSONObject.AdditionalProperties(
                                comment: nil,
                                type: JSONPrimitive.integer,
                                isReadOnly: false
                            )
                    ),
                    defaultValue: nil,
                    isRequired: true, // Expect this flag to be take precedence over the inner `additionalProperties`.
                    isReadOnly: true // Expect this flag to be take precedence over the inner `additionalProperties`.
                )
            ]
        )

        let expected = SwiftStruct(
            name: "Foo",
            comment: "Description of Foo.",
            properties: [
                SwiftStruct.Property(
                    name: "propertyWithAdditionalProperties",
                    comment: "Description of a property with nested additional properties.",
                    type: SwiftDictionary(
                        value: SwiftPrimitive<Int>()
                    ),
                    isOptional: false,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .static(value: "propertyWithAdditionalProperties")
                )
            ],
            conformance: []
        )

        let actual = try JSONToSwiftTypeTransformer().transform(jsonType: object)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(expected, actual[0])
    }

    // MARK: - Transforming `JSONOneOfs`

    func testTransformingRootJSONUnion() throws {
        let oneOfs = JSONUnionType(
            name: "RootMultitype",
            comment: "Root description",
            types: [
                .init(
                    name: "Child1",
                    type: JSONObject(
                        name: "Child1",
                        comment: nil,
                        properties: [
                            JSONObject.Property(
                                name: "child1Property",
                                comment: nil,
                                type: JSONPrimitive.integer,
                                defaultValue: nil,
                                isRequired: true,
                                isReadOnly: true
                            )
                        ]
                    )
                ),
                .init(
                    name: "Child2",
                    type: JSONObject(
                        name: "Child2",
                        comment: nil,
                        properties: [
                            JSONObject.Property(
                                name: "child2Property",
                                comment: nil,
                                type: JSONPrimitive.integer,
                                defaultValue: nil,
                                isRequired: true,
                                isReadOnly: true
                            )
                        ]
                    )
                )
            ]
        )

        let expected: [SwiftStruct] = [
            SwiftStruct(
                name: "Child1",
                comment: nil,
                properties: [
                    SwiftStruct.Property(
                        name: "child1Property",
                        comment: nil,
                        type: SwiftPrimitive<Int>(),
                        isOptional: false,
                        mutability: .immutable,
                        defaultValue: nil,
                        codingKey: .static(value: "child1Property")
                    )
                ],
                conformance: []
            ),
            SwiftStruct(
                name: "Child2",
                comment: nil,
                properties: [
                    SwiftStruct.Property(
                        name: "child2Property",
                        comment: nil,
                        type: SwiftPrimitive<Int>(),
                        isOptional: false,
                        mutability: .immutable,
                        defaultValue: nil,
                        codingKey: .static(value: "child2Property")
                    )
                ],
                conformance: []
            )
        ]

        let actual = try JSONToSwiftTypeTransformer().transform(jsonType: oneOfs)

        XCTAssertEqual(expected, actual)
    }

    func testTransformingNestedJSONUnion() throws {
        let object = JSONObject(
            name: "RootObject",
            comment: nil,
            properties: [
                JSONObject.Property(
                    name: "oneOfTypeProperty",
                    comment: "OneOf property description",
                    type: JSONUnionType(
                        name: "NestedOneOf",
                        comment: "OneOf property description",
                        types: [
                            .init(
                                name: "Child1",
                                type: JSONObject(
                                    name: "Child1",
                                    comment: nil,
                                    properties: [
                                        JSONObject.Property(
                                            name: "child1Property",
                                            comment: nil,
                                            type: JSONPrimitive.integer,
                                            defaultValue: nil,
                                            isRequired: true,
                                            isReadOnly: true
                                        )
                                    ]
                                )
                            ),
                            .init(
                                name: "Child2",
                                type: JSONObject(
                                    name: "Child2",
                                    comment: nil,
                                    properties: [
                                        JSONObject.Property(
                                            name: "child2Property",
                                            comment: nil,
                                            type: JSONPrimitive.integer,
                                            defaultValue: nil,
                                            isRequired: true,
                                            isReadOnly: true
                                        )
                                    ]
                                )
                            )
                        ]
                    ),
                    defaultValue: nil,
                    isRequired: true,
                    isReadOnly: true
                )
            ]
        )

        let expected = SwiftStruct(
            name: "RootObject",
            comment: nil,
            properties: [
                SwiftStruct.Property(
                    name: "oneOfTypeProperty",
                    comment: "OneOf property description",
                    type: SwiftAssociatedTypeEnum(
                        name: "NestedOneOf",
                        comment: "OneOf property description",
                        cases: [
                            SwiftAssociatedTypeEnum.Case(
                                label: "Child1",
                                associatedType: SwiftStruct(
                                    name: "Child1",
                                    comment: nil,
                                    properties: [
                                        SwiftStruct.Property(
                                            name: "child1Property",
                                            comment: nil,
                                            type: SwiftPrimitive<Int>(),
                                            isOptional: false,
                                            mutability: .immutable,
                                            defaultValue: nil,
                                            codingKey: .static(value: "child1Property")
                                        )
                                    ],
                                    conformance: []
                                )
                            ),
                            SwiftAssociatedTypeEnum.Case(
                                label: "Child2",
                                associatedType: SwiftStruct(
                                    name: "Child2",
                                    comment: nil,
                                    properties: [
                                        SwiftStruct.Property(
                                            name: "child2Property",
                                            comment: nil,
                                            type: SwiftPrimitive<Int>(),
                                            isOptional: false,
                                            mutability: .immutable,
                                            defaultValue: nil,
                                            codingKey: .static(value: "child2Property")
                                        )
                                    ],
                                    conformance: []
                                )
                            )
                        ],
                        conformance: []
                    ),
                    isOptional: false,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .static(value: "oneOfTypeProperty")
                )
            ],
            conformance: []
        )

        let actual = try JSONToSwiftTypeTransformer().transform(jsonType: object)

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(expected, actual[0])
    }

    func testTransformingRootJSONOneOfsWithNestedJSONUnion() throws {
        let rootOneOfs = JSONUnionType(
            name: "Root oneOf",
            comment: "Root oneOf comment",
            types: [
                .init(
                    name: "Root 1",
                    type: JSONUnionType(
                        name: "Nested oneOf",
                        comment: "Nested oneOf comment",
                        types: [
                            .init(
                                name: "Nested 1A",
                                type: JSONObject(
                                    name: "Nested 1A",
                                    comment: nil,
                                    properties: []
                                )
                            ),
                            .init(
                                name: "Nested 1B",
                                type: JSONObject(
                                    name: "Nested 1B",
                                    comment: nil,
                                    properties: []
                                )
                            ),
                        ]
                    )
                ),
                .init(
                    name: "Root 2",
                    type: JSONUnionType(
                        name: "Nested oneOf",
                        comment: "Nested oneOf comment",
                        types: [
                            .init(
                                name: "Nested 2A",
                                type: JSONObject(
                                    name: "Nested 2A",
                                    comment: nil,
                                    properties: []
                                )
                            ),
                            .init(
                                name: "Nested 2B",
                                type: JSONObject(
                                    name: "Nested 2B",
                                    comment: nil,
                                    properties: []
                                )
                            ),
                        ]
                    )
                )
            ]
        )

        let expected: [SwiftStruct] = [
            SwiftStruct(name: "Nested 1A", comment: nil, properties: [], conformance: []),
            SwiftStruct(name: "Nested 1B", comment: nil, properties: [], conformance: []),
            SwiftStruct(name: "Nested 2A", comment: nil, properties: [], conformance: []),
            SwiftStruct(name: "Nested 2B", comment: nil, properties: [], conformance: []),
        ]

        let actual = try JSONToSwiftTypeTransformer().transform(jsonType: rootOneOfs)
        XCTAssertEqual(expected, actual)
    }

    func testTransformingRootJSONUnionWithMixedOneOfTypes() throws {
        let rootOneOfs = JSONUnionType(
            name: "Root oneOf",
            comment: "Root oneOf comment",
            types: [
                .init(
                    name: "Root 1",
                    type: JSONUnionType(
                        name: "Nested oneOf",
                        comment: "Nested oneOf comment",
                        types: [
                            .init(
                                name: "Nested oneOf A",
                                type: JSONObject(
                                    name: "JSONObject 1A",
                                    comment: nil,
                                    properties: []
                                )
                            ),
                            .init(
                                name: "Nested oneOf B",
                                type: JSONObject(
                                    name: "JSONObject 1B",
                                    comment: nil,
                                    properties: []
                                )
                            ),
                        ]
                    )
                ),
                .init(
                    name: "Root 2",
                    type: JSONObject(
                        name: "JSONObject 2",
                        comment: nil,
                        properties: []
                    )
                )
            ]
        )

        let expected: [SwiftStruct] = [
            SwiftStruct(name: "JSONObject 1A", comment: nil, properties: [], conformance: []),
            SwiftStruct(name: "JSONObject 1B", comment: nil, properties: [], conformance: []),
            SwiftStruct(name: "JSONObject 2", comment: nil, properties: [], conformance: []),
        ]

        let actual = try JSONToSwiftTypeTransformer().transform(jsonType: rootOneOfs)
        XCTAssertEqual(expected, actual)
    }
}
