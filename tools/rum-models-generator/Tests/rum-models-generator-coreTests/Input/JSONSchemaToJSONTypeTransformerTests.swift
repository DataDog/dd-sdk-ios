/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import RUMModelsGeneratorCore

final class JSONSchemaToJSONTypeTransformerTests: XCTestCase {
    func testTransformingJSONSchemaIntoJSONObject() throws {
        let referencedSchema1 = """
        {
            "$id": "referenced-schema1.json",
            "type": "object",
            "properties": {
                "bar": {
                    "type": "object",
                    "description": "Description of Bar.",
                    "properties": {
                        "property1": {
                            "type": "string",
                            "description": "Description of Bar's `property1`.",
                            "readOnly": true
                        }
                    }
                }
            }
        }
        """

        let referencedSchema2 = """
        {
            "$id": "referenced-schema2.json",
            "type": "object",
            "properties": {
                "bar": {
                    "type": "object",
                    "description": "Description of Bar.",
                    "properties": {
                        "property2": {
                            "type": "string",
                            "description": "Description of Bar's `property2`.",
                            "readOnly": false
                        }
                    },
                    "required": ["property2"]
                }
            }
        }
        """

        let mainSchema = """
        {
            "type": "object",
            "title": "Foo",
            "description": "Description of Foo.",
            "allOf": [
                { "$ref": "referenced-schema1.json" },
                { "$ref": "referenced-schema2.json" },
                {
                    "properties": {
                        "property1": {
                            "type": "string",
                            "description": "Description of Foo's `property1`.",
                            "enum": ["case1", "case2", "case3", "case4"],
                            "const": "case2"
                        },
                        "property2": {
                            "type": "array",
                            "description": "Description of Foo's `property2`.",
                            "items": {
                                "type": "string",
                                "enum": ["option1", "option2", "option3", "option4"]
                            },
                            "readOnly": false
                        },
                        "propertyWithAdditionalProperties": {
                            "type": "object",
                            "description": "Description of a property with nested additional properties.",
                            "additionalProperties": {
                                 "type": "integer",
                                 "minimum": 0,
                                 "readOnly": true
                            },
                            "readOnly": true
                        }
                    },
                    "additionalProperties": {
                        "type": "string",
                        "description": "Additional properties of Foo.",
                        "readOnly": true
                    },
                    "required": ["property1"],
                }
            ]
        }
        """

        let expected = JSONObject(
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
                        values: ["case1", "case2", "case3", "case4"]
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
                            values: ["option1", "option2", "option3", "option4"]
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

        let jsonSchema = try JSONSchemaReader()
            .readJSONSchema(
                from: File(name: "main-schema", content: mainSchema.data(using: .utf8)!),
                resolvingAgainst: [
                    File(name: "referenced-schema-1", content: referencedSchema1.data(using: .utf8)!),
                    File(name: "referenced-schema-2", content: referencedSchema2.data(using: .utf8)!),
                ]
            )

        let actual = try JSONSchemaToJSONTypeTransformer().transform(jsonSchemas: [jsonSchema])

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(expected, actual[0])
    }
}
