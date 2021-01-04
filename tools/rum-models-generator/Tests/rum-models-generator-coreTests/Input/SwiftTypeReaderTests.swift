/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import RUMModelsGeneratorCore

final class SwiftTypeReaderTests: XCTestCase {
    func testReadingSwiftStructFromJSONObject() throws {
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
                                defaultVaule: nil,
                                isRequired: false,
                                isReadOnly: true
                            ),
                            JSONObject.Property(
                                name: "property2",
                                comment: "Description of Bar's `property2`.",
                                type: JSONPrimitive.string,
                                defaultVaule: nil,
                                isRequired: true,
                                isReadOnly: false
                            )
                        ]
                    ),
                    defaultVaule: nil,
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
                    defaultVaule: JSONObject.Property.DefaultValue.string(value: "case2"),
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
                    defaultVaule: nil,
                    isRequired: false,
                    isReadOnly: false
                )
            ]
        )

        let actual = try SwiftTypeReader().readSwiftStruct(from: object)

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
                                defaultVaule: nil,
                                codingKey: "property1"
                            ),
                            SwiftStruct.Property(
                                name: "property2",
                                comment: "Description of Bar's `property2`.",
                                type: SwiftPrimitive<String>(),
                                isOptional: false,
                                isMutable: true,
                                defaultVaule: nil,
                                codingKey: "property2"
                            )
                        ],
                        conformance: []
                    ),
                    isOptional: true,
                    isMutable: false,
                    defaultVaule: nil,
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
                    defaultVaule: SwiftEnum.Case(label: "case2", rawValue: "case2"),
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
                    defaultVaule: nil,
                    codingKey: "property2"
                )
            ],
            conformance: []
        )

        XCTAssertEqual(expected, actual)
    }
}
