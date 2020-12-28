/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import RUMModelsGeneratorCore

final class SwiftPrinterTests: XCTestCase {
    func testPrintingSwiftStruct() throws {
        let `struct` = SwiftStruct(
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
                        conformance: [codableProtocol]
                    ),
                    isOptional: true,
                    isMutable: false,
                    defaultVaule: nil,
                    codingKey: "bar"
                ),
                SwiftStruct.Property(
                    name: "property1",
                    comment: "Description of FooBar's `property1`.",
                    type: SwiftEnum(
                        name: "Property1",
                        comment: "Description of FooBar's `property1`.",
                        cases: [
                            SwiftEnum.Case(label: "case1", rawValue: "case 1"),
                            SwiftEnum.Case(label: "case2", rawValue: "case 2"),
                            SwiftEnum.Case(label: "case3", rawValue: "case 3"),
                            SwiftEnum.Case(label: "case4", rawValue: "case 4"),
                        ],
                        conformance: [codableProtocol]
                    ),
                    isOptional: false,
                    isMutable: false,
                    defaultVaule: SwiftEnum.Case(label: "case2", rawValue: "case2"),
                    codingKey: "property1"
                ),
                SwiftStruct.Property(
                    name: "property2",
                    comment: "Description of FooBar's `property2`.",
                    type: SwiftArray(
                        element: SwiftEnum(
                            name: "Property2",
                            comment: nil,
                            cases: [
                                SwiftEnum.Case(label: "option1", rawValue: "option-1"),
                                SwiftEnum.Case(label: "option2", rawValue: "option-2"),
                                SwiftEnum.Case(label: "option3", rawValue: "option-3"),
                                SwiftEnum.Case(label: "option4", rawValue: "option-4"),
                            ],
                            conformance: [codableProtocol]
                        )
                    ),
                    isOptional: true,
                    isMutable: true,
                    defaultVaule: nil,
                    codingKey: "property2"
                )
            ],
            conformance: [SwiftProtocol(name: "RUMDataModel", conformance: [codableProtocol])]
        )

        let actual = try SwiftPrinter().print(swiftStruct: `struct`)

        let expected = """
        /// Description of FooBar.
        internal struct FooBar: RUMDataModel {
            /// Description of Bar.
            let bar: BAR?

            /// Description of FooBar's `property1`.
            let property1: Property1 = .case2

            /// Description of FooBar's `property2`.
            var property2: [Property2]?

            enum CodingKeys: String, CodingKey {
                case bar = "bar"
                case property1 = "property1"
                case property2 = "property2"
            }

            /// Description of Bar.
            internal struct BAR: Codable {
                /// Description of Bar's `property1`.
                let property1: String?

                /// Description of Bar's `property2`.
                var property2: String

                enum CodingKeys: String, CodingKey {
                    case property1 = "property1"
                    case property2 = "property2"
                }
            }

            /// Description of FooBar's `property1`.
            internal enum Property1: String, Codable {
                case case1 = "case 1"
                case case2 = "case 2"
                case case3 = "case 3"
                case case4 = "case 4"
            }

            internal enum Property2: String, Codable {
                case option1 = "option-1"
                case option2 = "option-2"
                case option3 = "option-3"
                case option4 = "option-4"
            }
        }

        """

        XCTAssertEqual(expected, actual)
    }
}
