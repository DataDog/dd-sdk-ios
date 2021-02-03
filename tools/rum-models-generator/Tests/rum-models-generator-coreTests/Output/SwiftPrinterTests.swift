/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-2020 Datadog, Inc.
*/

import XCTest
@testable import RUMModelsGeneratorCore

final class SwiftPrinterTests: XCTestCase {
    private let `struct` = SwiftStruct(
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
                    additionalProperties: SwiftStruct.Property(
                        name: "additionalProperties",
                        comment: "Additional properties of Bar.",
                        type: SwiftPrimitive<String>(),
                        isOptional: true,
                        isMutable: true,
                        defaultValue: nil,
                        codingKey: "additionalProperties"
                    ),
                    conformance: [codableProtocol]
                ),
                isOptional: true,
                isMutable: false,
                defaultValue: nil,
                codingKey: "bar"
            ),
            SwiftStruct.Property(
                name: "bizz",
                comment: "Description of FooBar's `bizz`.",
                type: SwiftEnum(
                    name: "Bizz",
                    comment: "Description of FooBar's `bizz`.",
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
                defaultValue: SwiftEnum.Case(label: "case2", rawValue: "case2"),
                codingKey: "bizz"
            ),
            SwiftStruct.Property(
                name: "buzz",
                comment: "Description of FooBar's `buzz`.",
                type: SwiftArray(
                    element: SwiftEnum(
                        name: "Buzz",
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
                defaultValue: nil,
                codingKey: "buzz"
            )
        ],
        additionalProperties: SwiftStruct.Property(
            name: "additionalProperties",
            comment: "Additional properties of FooBar.",
            type: SwiftPrimitive<Int>(),
            isOptional: true,
            isMutable: false,
            defaultValue: nil,
            codingKey: "additionalProperties"
        ),
        conformance: [SwiftProtocol(name: "RUMDataModel", conformance: [codableProtocol])]
    )

    private let `enum` = SwiftEnum(
        name: "BizzBuzz",
        comment: nil,
        cases: [
            SwiftEnum.Case(label: "case1", rawValue: "case 1"),
            SwiftEnum.Case(label: "case2", rawValue: "case 2"),
            SwiftEnum.Case(label: "case3", rawValue: "case 3"),
        ],
        conformance: [codableProtocol]
    )

    func testPrintingSwiftStruct() throws {
        let printer = SwiftPrinter()
        let actual = try printer.print(swiftTypes: [`struct`, `enum`])

        let expected = """

        fileprivate struct DynamicCodingKey: CodingKey {
            var stringValue: String
            var intValue: Int?
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
            init(_ string: String) { self.stringValue = string }
        }

        /// Description of FooBar.
        public struct FooBar: RUMDataModel {
            /// Description of Bar.
            public let bar: BAR?

            /// Description of FooBar's `bizz`.
            public let bizz: Bizz = .case2

            /// Description of FooBar's `buzz`.
            public var buzz: [Buzz]?

            /// Additional properties of FooBar.
            public let additionalProperties: [String: Int]?

            enum CodingKeys: String, CodingKey {
                case bar = "bar"
                case bizz = "bizz"
                case buzz = "buzz"
            }

            func encode(to encoder: Encoder) throws {
                var propsContainer = encoder.container(keyedBy: CodingKeys.self)
                try propsContainer.encode(bar, forKey: .bar)
                try propsContainer.encode(bizz, forKey: .bizz)
                try propsContainer.encode(buzz, forKey: .buzz)

                var addPropsContainer = encoder.container(keyedBy: DynamicCodingKey.self)
                try additionalProperties.forEach { key, value in
                    try addPropsContainer.encode(value, forKey: DynamicCodingKey(key))
                }
            }

            init(from decoder: Decoder) throws {
                var propsContainer = decoder.container(keyedBy: CodingKeys.self)
                bar = try propsContainer.decode(BAR.self, forKey: .bar)
                bizz = try propsContainer.decode(Bizz.self, forKey: .bizz)
                buzz = try propsContainer.decode([Buzz].self, forKey: .buzz)

                var addPropsContainer = decoder.container(keyedBy: DynamicCodingKey.self)
                let allKeys = addPropsContainer.allKeys
                try allKeys.forEach { key in
                    let value = try addPropsContainer.decode(Int.self, forKey: key)
                    additionalProperties[key] = value
                }
            }

            /// Description of Bar.
            public struct BAR: Codable {
                /// Description of Bar's `property1`.
                public let property1: String?

                /// Description of Bar's `property2`.
                public var property2: String

                /// Additional properties of Bar.
                public var additionalProperties: [String: String]?

                enum CodingKeys: String, CodingKey {
                    case property1 = "property1"
                    case property2 = "property2"
                }

                func encode(to encoder: Encoder) throws {
                    var propsContainer = encoder.container(keyedBy: CodingKeys.self)
                    try propsContainer.encode(property1, forKey: .property1)
                    try propsContainer.encode(property2, forKey: .property2)

                    var addPropsContainer = encoder.container(keyedBy: DynamicCodingKey.self)
                    try additionalProperties.forEach { key, value in
                        try addPropsContainer.encode(value, forKey: DynamicCodingKey(key))
                    }
                }

                init(from decoder: Decoder) throws {
                    var propsContainer = decoder.container(keyedBy: CodingKeys.self)
                    property1 = try propsContainer.decode(String.self, forKey: .property1)
                    property2 = try propsContainer.decode(String.self, forKey: .property2)

                    var addPropsContainer = decoder.container(keyedBy: DynamicCodingKey.self)
                    let allKeys = addPropsContainer.allKeys
                    try allKeys.forEach { key in
                        let value = try addPropsContainer.decode(String.self, forKey: key)
                        additionalProperties[key] = value
                    }
                }
            }

            /// Description of FooBar's `bizz`.
            public enum Bizz: String, Codable {
                case case1 = "case 1"
                case case2 = "case 2"
                case case3 = "case 3"
                case case4 = "case 4"
            }

            public enum Buzz: String, Codable {
                case option1 = "option-1"
                case option2 = "option-2"
                case option3 = "option-3"
                case option4 = "option-4"
            }
        }

        public enum BizzBuzz: String, Codable {
            case case1 = "case 1"
            case case2 = "case 2"
            case case3 = "case 3"
        }

        """

        XCTAssertEqual(expected, actual)
    }
}
