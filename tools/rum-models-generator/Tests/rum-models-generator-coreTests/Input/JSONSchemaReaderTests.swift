/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import RUMModelsGeneratorCore

final class JSONSchemaReaderTests: XCTestCase {
    func testReadingSchemaWithTypedAdditionalProperties() throws {
        let mainSchema = """
        {
            "$id": "Schema ID",
            "type": "object",
            "title": "Schema title",
            "description": "Schema description.",
            "properties": {
                "property1": {
                    "type": "string",
                    "description": "Description of `property1`.",
                    "enum": ["case1", "case2", "case3", "case4"],
                    "const": "case2"
                },
                "property2": {
                    "type": "array",
                    "description": "Description of `property2`.",
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
                         "readOnly": true
                    },
                    "readOnly": true
                }
            },
            "additionalProperties": {
                "type": "string",
                "description": "Additional properties of main schema.",
                "readOnly": true
            },
            "required": ["property1"]
        }
        """

        let schema = try JSONSchemaReader()
            .readJSONSchema(
                from: File(name: "main-schema", content: mainSchema.data(using: .utf8)!),
                resolvingAgainst: []
            )

        XCTAssertEqual(schema.id, "Schema ID")
        XCTAssertEqual(schema.title, "Schema title")
        XCTAssertEqual(schema.description, "Schema description.")

        XCTAssertEqual(schema.properties?.count, 3)

        let property1 = try XCTUnwrap(schema.properties?["property1"])
        XCTAssertEqual(property1.type, .string)
        XCTAssertEqual(property1.description, "Description of `property1`.")
        XCTAssertEqual(property1.enum, ["case1", "case2", "case3", "case4"])
        XCTAssertEqual(property1.const!.value, .string(value: "case2"))

        let property2 = try XCTUnwrap(schema.properties?["property2"])
        XCTAssertEqual(property2.type, .array)
        XCTAssertEqual(property2.description, "Description of `property2`.")
        XCTAssertEqual(property2.items?.type, .string)
        XCTAssertEqual(property2.items?.enum, ["option1", "option2", "option3", "option4"])
        XCTAssertEqual(property2.readOnly, false)

        let property3 = try XCTUnwrap(schema.properties?["propertyWithAdditionalProperties"])
        XCTAssertEqual(property3.type, .object)
        XCTAssertEqual(property3.description, "Description of a property with nested additional properties.")
        XCTAssertEqual(property3.additionalProperties?.type, .integer)
        XCTAssertEqual(property3.additionalProperties?.readOnly, true)
        XCTAssertEqual(property3.readOnly, true)

        XCTAssertEqual(schema.additionalProperties?.type, .string)
        XCTAssertEqual(schema.additionalProperties?.description, "Additional properties of main schema.")
        XCTAssertEqual(schema.additionalProperties?.readOnly, true)

        XCTAssertEqual(schema.required, ["property1"])
    }

    func testReadingSchemaWithAdditionalPropertiesWithNoType() throws {
        let mainSchema = """
        {
            "additionalProperties": true,
            "properties": {
                "foo": {
                    "type": "string",
                    "readOnly": true
                },
                "bar": {
                    "type": "object",
                    "additionalProperties": true
                }
            }
        }
        """

        let schema = try JSONSchemaReader()
            .readJSONSchema(
                from: File(name: "main-schema", content: mainSchema.data(using: .utf8)!),
                resolvingAgainst: []
            )

        XCTAssertEqual(schema.properties?.count, 2)

        XCTAssertNotNil(schema.properties?["foo"])
        XCTAssertNil(schema.properties?["foo"]?.additionalProperties)

        XCTAssertNotNil(schema.properties?["bar"])
        XCTAssertNotNil(schema.properties?["bar"]?.additionalProperties)
        XCTAssertEqual(schema.properties?["bar"]?.additionalProperties?.type, .object)

        XCTAssertEqual(schema.additionalProperties?.type, .object)
    }
}
