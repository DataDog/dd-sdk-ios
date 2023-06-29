/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
@testable import CodeGeneration

final class JSONSchemaToJSONTypeTransformerTests: XCTestCase {
    func testTransformingJSONSchemaIntoJSONObject() throws {
        let expected = JSONUnionType(
            name: "Schema title",
            comment: "Fixture schema",
            types: [
                .init(
                    name: "Foo",
                    type: JSONObject(
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
                                name: "stringEnumProperty",
                                comment: "Description of Foo's `stringEnumProperty`.",
                                type: JSONEnumeration(
                                    name: "stringEnumProperty",
                                    comment: "Description of Foo's `stringEnumProperty`.",
                                    values: [.string(value: "case1"), .string(value: "case2"), .string(value: "case3"), .string(value: "case4")]
                                ),
                                defaultValue: JSONObject.Property.DefaultValue.string(value: "case2"),
                                isRequired: true,
                                isReadOnly: true
                            ),
                            JSONObject.Property(
                                name: "integerEnumProperty",
                                comment: "Description of Foo's `integerEnumProperty`.",
                                type: JSONEnumeration(
                                    name: "integerEnumProperty",
                                    comment: "Description of Foo's `integerEnumProperty`.",
                                    values: [.integer(value: 1), .integer(value: 2), .integer(value: 3), .integer(value: 4)]
                                ),
                                defaultValue: JSONObject.Property.DefaultValue.integer(value: 3),
                                isRequired: false,
                                isReadOnly: true
                            ),
                            JSONObject.Property(
                                name: "arrayProperty",
                                comment: "Description of Foo's `arrayProperty`.",
                                type: JSONArray(
                                    element: JSONEnumeration(
                                        name: "arrayProperty",
                                        comment: nil,
                                        values: [.string(value: "option1"), .string(value: "option2"), .string(value: "option3"), .string(value: "option4")]
                                    )
                                ),
                                defaultValue: nil,
                                isRequired: false,
                                isReadOnly: false
                            ),
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
                                            isReadOnly: true
                                        )
                                ),
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
                )
            ]
        )

        let file = Bundle.module.url(forResource: "Fixtures/fixture-json-schema-to-json-type-transformer", withExtension: "json")!

        let jsonSchema = try JSONSchemaReader().read(file)

        let actual = try JSONSchemaToJSONTypeTransformer().transform(jsonSchema: jsonSchema)
        XCTAssertEqual(expected, actual as? JSONUnionType)
    }

    func testTransformingJSONSchemaWithUnionTypeIntoJSONObject() throws {
        let expected = JSONUnionType(
            name: "Schema title",
            comment: "Schema description",
            types: [
                .init(
                    name: "A",
                    type: JSONObject(
                        name: "A",
                        comment: "A description",
                        properties: [
                            JSONObject.Property(
                                name: "propertyInA",
                                comment: nil,
                                type: JSONPrimitive.string,
                                defaultValue: nil,
                                isRequired: false,
                                isReadOnly: true
                            ),
                        ]
                    )
                ),
                .init(
                    name: "B",
                    type: JSONObject(
                        name: "B",
                        comment: "B description",
                        properties: [
                            JSONObject.Property(
                                name: "propertyInB",
                                comment: nil,
                                type: JSONPrimitive.integer,
                                defaultValue: nil,
                                isRequired: false,
                                isReadOnly: true
                            ),
                        ]
                    )
                ),
                .init(
                    name: "C",
                    type: JSONUnionType(
                        name: "C",
                        comment: "C description",
                        types: [
                            .init(
                                name: "C1",
                                type: JSONObject(
                                    name: "C1",
                                    comment: nil,
                                    properties: [
                                        JSONObject.Property(
                                            name: "propertyInC1",
                                            comment: nil,
                                            type: JSONPrimitive.integer,
                                            defaultValue: nil,
                                            isRequired: false,
                                            isReadOnly: true
                                        ),
                                    ]
                                )
                            ),
                            .init(
                                name: "C2",
                                type: JSONObject(
                                    name: "C2",
                                    comment: nil,
                                    properties: [
                                        JSONObject.Property(
                                            name: "propertyInC2",
                                            comment: nil,
                                            type: JSONPrimitive.string,
                                            defaultValue: nil,
                                            isRequired: false,
                                            isReadOnly: true
                                        ),
                                    ]
                                )
                            )
                        ]
                    )
                )
            ]
        )

        let file = Bundle.module.url(forResource: "Fixtures/fixture-schema-with-oneof", withExtension: "json")!

        let jsonSchema = try JSONSchemaReader().read(file)

        let actual = try JSONSchemaToJSONTypeTransformer().transform(jsonSchema: jsonSchema)
        XCTAssertEqual(expected, actual as? JSONUnionType)
    }

    func testTransformingJSONSchemaWithNoExplicitEnumTypeIntoJSONObject() throws {
        let expected = JSONObject(
            name: "Schema title",
            comment: "Schema description.",
            properties: [
                JSONObject.Property(
                    name: "stringEnumProperty",
                    comment: "Description of `stringEnumProperty` without explicit type.",
                    type: JSONEnumeration(
                        name: "stringEnumProperty",
                        comment: "Description of `stringEnumProperty` without explicit type.",
                        values: [.string(value: "case1"), .string(value: "case2"), .string(value: "case3"), .string(value: "case4")]
                    ),
                    defaultValue: nil,
                    isRequired: false,
                    isReadOnly: true
                ),
                JSONObject.Property(
                    name: "integerEnumProperty",
                    comment: "Description of `integerEnumProperty` without explicit type.",
                    type: JSONEnumeration(
                        name: "integerEnumProperty",
                        comment: "Description of `integerEnumProperty` without explicit type.",
                        values: [.integer(value: 1), .integer(value: 2), .integer(value: 3), .integer(value: 4)]
                    ),
                    defaultValue: nil,
                    isRequired: false,
                    isReadOnly: true
                )
            ]
        )

        let file = Bundle.module.url(forResource: "Fixtures/fixture-schema-with-typeless-enum", withExtension: "json")!

        let jsonSchema = try JSONSchemaReader().read(file)

        let actual = try JSONSchemaToJSONTypeTransformer().transform(jsonSchema: jsonSchema)
        XCTAssertEqual(expected, actual as? JSONObject)
    }
}
