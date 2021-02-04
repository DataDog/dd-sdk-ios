/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import RUMModelsGeneratorCore

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
                            JSONObject.Property(
                                name: "additionalProperties",
                                comment: nil,
                                type: JSONPrimitive.integer,
                                defaultValue: nil,
                                isRequired: false,
                                isReadOnly: true
                            )
                    ),
                    defaultValue: nil,
                    isRequired: false,
                    isReadOnly: true
                )
            ],
            additionalProperties: JSONObject.Property(
                name: "additionalProperties",
                comment: "Additional properties of Foo.",
                type: JSONPrimitive.string,
                defaultValue: nil,
                isRequired: false,
                isReadOnly: true
            )
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
                                isMutable: false,
                                defaultValue: nil,
                                codingKey: "property1"
                            ),
                            SwiftStruct.Property(
                                name: "property2",
                                comment: "Description of Bar's `property2`.",
                                type: SwiftPrimitive<String>(),
                                isOptional: false,
                                isMutable: true,
                                defaultValue: nil,
                                codingKey: "property2"
                            )
                        ],
                        conformance: []
                    ),
                    isOptional: true,
                    isMutable: true, // should be mutable as at least one of the `Bar's` properties is mutable
                    defaultValue: nil,
                    codingKey: "bar"
                ),
                SwiftStruct.Property(
                    name: "property1",
                    comment: "Description of Foo's `property1`.",
                    type: SwiftEnum(
                        name: "property1",
                        comment: "Description of Foo's `property1`.",
                        cases: [
                            SwiftEnum.Case(label: "case1", rawValue: "case1"),
                            SwiftEnum.Case(label: "case2", rawValue: "case2"),
                            SwiftEnum.Case(label: "case3", rawValue: "case3"),
                            SwiftEnum.Case(label: "case4", rawValue: "case4"),
                        ],
                        conformance: []
                    ),
                    isOptional: false,
                    isMutable: false,
                    defaultValue: SwiftEnum.Case(label: "case2", rawValue: "case2"),
                    codingKey: "property1"
                ),
                SwiftStruct.Property(
                    name: "property2",
                    comment: "Description of Foo's `property2`.",
                    type: SwiftArray(
                        element: SwiftEnum(
                            name: "property2",
                            comment: nil,
                            cases: [
                                SwiftEnum.Case(label: "option1", rawValue: "option1"),
                                SwiftEnum.Case(label: "option2", rawValue: "option2"),
                                SwiftEnum.Case(label: "option3", rawValue: "option3"),
                                SwiftEnum.Case(label: "option4", rawValue: "option4"),
                            ],
                            conformance: []
                        )
                    ),
                    isOptional: true,
                    isMutable: true,
                    defaultValue: nil,
                    codingKey: "property2"
                ),
                SwiftStruct.Property(
                    name: "propertyWithAdditionalProperties",
                    comment: "Description of a property with nested additional properties.",
                    type: SwiftStruct(
                        name: "propertyWithAdditionalProperties",
                        comment: "Description of a property with nested additional properties.",
                        properties: [],
                        additionalProperties: SwiftStruct.Property(
                            name: "additionalProperties",
                            comment: nil,
                            type: SwiftPrimitive<Int>(),
                            isOptional: true,
                            isMutable: false,
                            defaultValue: nil,
                            codingKey: "additionalProperties"
                        ),
                        conformance: []
                    ),
                    isOptional: true,
                    isMutable: false,
                    defaultValue: nil,
                    codingKey: "propertyWithAdditionalProperties"
                )
            ],
            additionalProperties: SwiftStruct.Property(
                name: "additionalProperties",
                comment: "Additional properties of Foo.",
                type: SwiftPrimitive<String>(),
                isOptional: true,
                isMutable: false,
                defaultValue: nil,
                codingKey: "additionalProperties"
            ),
            conformance: []
        )

        let actual = try JSONToSwiftTypeTransformer().transform(jsonObjects: [object])

        XCTAssertEqual(actual.count, 1)
        XCTAssertEqual(expected, actual[0])
    }
}
