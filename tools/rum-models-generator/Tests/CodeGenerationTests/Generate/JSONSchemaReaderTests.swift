/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
@testable import CodeGeneration

final class JSONSchemaReaderTests: XCTestCase {
    func testReadingSchemaWithTypedAdditionalProperties() throws {
        let file = Bundle.module.url(forResource: "Fixtures/fixture-reading-schema-with-typed-additional-properties", withExtension: "json")!

        let schema = try JSONSchemaReader().read(file)

        XCTAssertEqual(schema.id, "Schema ID")
        XCTAssertEqual(schema.title, "Schema title")
        XCTAssertEqual(schema.description, "Schema description.")

        XCTAssertEqual(schema.properties?.count, 4)

        let property1 = try XCTUnwrap(schema.properties?["stringEnumProperty"])
        XCTAssertEqual(property1.type, .string)
        XCTAssertEqual(property1.description, "Description of `stringEnumProperty`.")
        XCTAssertEqual(property1.enum, [.string("case1"), .string("case2"), .string("case3"), .string("case4")])
        XCTAssertEqual(property1.const!.value, .string(value: "case2"))

        let property2 = try XCTUnwrap(schema.properties?["integerEnumProperty"])
        XCTAssertEqual(property2.type, .number)
        XCTAssertEqual(property2.description, "Description of `integerEnumProperty`.")
        XCTAssertEqual(property2.enum, [.integer(1), .integer(2), .integer(3), .integer(4)])
        XCTAssertEqual(property2.const!.value, .integer(value: 3))

        let property3 = try XCTUnwrap(schema.properties?["arrayProperty"])
        XCTAssertEqual(property3.type, .array)
        XCTAssertEqual(property3.description, "Description of `arrayProperty`.")
        XCTAssertEqual(property3.items?.type, .string)
        XCTAssertEqual(property3.items?.enum, [.string("option1"), .string("option2"), .string("option3"), .string("option4")])
        XCTAssertTrue(property3.readOnly == false)

        let property4 = try XCTUnwrap(schema.properties?["propertyWithAdditionalProperties"])
        XCTAssertEqual(property4.type, .object)
        XCTAssertEqual(property4.description, "Description of a property with nested additional properties.")
        XCTAssertEqual(property4.additionalProperties?.type, .integer)
        XCTAssertEqual(property4.additionalProperties?.readOnly, true)
        XCTAssertTrue(property4.readOnly == true)

        XCTAssertEqual(schema.additionalProperties?.type, .string)
        XCTAssertEqual(schema.additionalProperties?.description, "Additional properties of main schema.")
        XCTAssertEqual(schema.additionalProperties?.readOnly, true)

        XCTAssertEqual(schema.required, ["property1"])
    }

    func testReadingSchemaWithAdditionalPropertiesWithNoType() throws {
        let file = Bundle.module.url(forResource: "Fixtures/fixture-reading-schema-with-additional-properties-with-no-type", withExtension: "json")!

        let schema = try JSONSchemaReader().read(file)
        XCTAssertEqual(schema.properties?.count, 2)

        XCTAssertNotNil(schema.properties?["foo"])
        XCTAssertNil(schema.properties?["foo"]?.additionalProperties)

        XCTAssertNotNil(schema.properties?["bar"])
        XCTAssertNotNil(schema.properties?["bar"]?.additionalProperties)
        XCTAssertEqual(schema.properties?["bar"]?.additionalProperties?.type, .object)

        XCTAssertEqual(schema.additionalProperties?.type, .object)
    }

    func testReadingSchemaWithOneOf() throws {
        let file = Bundle.module.url(forResource: "Fixtures/fixture-schema-with-oneof", withExtension: "json")!

        let schema = try JSONSchemaReader().read(file)
        XCTAssertEqual(schema.oneOf?.count, 3)
        XCTAssertEqual(schema.oneOf?[0].properties?["propertyInA"]?.type, .string)
        XCTAssertEqual(schema.oneOf?[1].properties?["propertyInB"]?.type, .integer)
        XCTAssertEqual(schema.oneOf?[2].oneOf?.count, 2)
        XCTAssertEqual(schema.oneOf?[2].oneOf?[0].properties?["propertyInC1"]?.type, .integer)
        XCTAssertEqual(schema.oneOf?[2].oneOf?[1].properties?["propertyInC2"]?.type, .string)
    }

    func testReadingSchemaWithAnyOf() throws {
        let file = Bundle.module.url(forResource: "Fixtures/fixture-schema-with-anyof", withExtension: "json")!

        let schema = try JSONSchemaReader().read(file)
        XCTAssertEqual(schema.anyOf?.count, 3)
        XCTAssertEqual(schema.anyOf?[0].properties?["propertyInA"]?.type, .string)
        XCTAssertEqual(schema.anyOf?[1].properties?["propertyInB"]?.type, .integer)
        XCTAssertEqual(schema.anyOf?[2].oneOf?.count, 2)
        XCTAssertEqual(schema.anyOf?[2].oneOf?[0].properties?["propertyInC1"]?.type, .integer)
        XCTAssertEqual(schema.anyOf?[2].oneOf?[1].properties?["propertyInC2"]?.type, .string)
    }

    func testReadingSchemaWithOneOfWithoutTitle() throws {
        let file = Bundle.module.url(forResource: "Fixtures/fixture-schema-with-oneof-without-title", withExtension: "json")!

        let schema = try JSONSchemaReader().read(file)

        XCTAssertEqual(schema.title, "TelemetryCommonFeaturesUsage")

        XCTAssertEqual(schema.oneOf?.count, 3)

        XCTAssertEqual(schema.oneOf?[0].properties?["feature"]?.type, .string)
        XCTAssertEqual(schema.oneOf?[0].properties?["feature"]?.description, "setTrackingConsent API")
        XCTAssertEqual(schema.oneOf?[0].properties?["feature"]?.const, .init(value: .string(value: "set-tracking-consent")))

        XCTAssertEqual(schema.oneOf?[0].properties?["tracking_consent"]?.type, .string)
        XCTAssertEqual(schema.oneOf?[0].properties?["tracking_consent"]?.enum, [.string("granted"), .string("not-granted"), .string("pending")])
        XCTAssertEqual(schema.oneOf?[0].properties?["tracking_consent"]?.description, "The tracking consent value set by the user")

        XCTAssertEqual(schema.oneOf?[1].properties?["feature"]?.type, .string)
        XCTAssertEqual(schema.oneOf?[1].properties?["feature"]?.description, "stopSession API")
        XCTAssertEqual(schema.oneOf?[1].properties?["feature"]?.const, .init(value: .string(value: "stop-session")))
    }
}
