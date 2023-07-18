/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
@testable import CodeGeneration

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
                    name: "bizz",
                    comment: "Description of FooBar's `bizz`.",
                    type: SwiftEnum(
                        name: "Bizz",
                        comment: "Description of FooBar's `bizz`.",
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
                    codingKey: .static(value: "bizz")
                ),
                SwiftStruct.Property(
                    name: "buzz",
                    comment: "Description of FooBar's `buzz`.",
                    type: SwiftArray(
                        element: SwiftEnum(
                            name: "Buzz",
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
                    codingKey: .static(value: "buzz")
                ),
                SwiftStruct.Property(
                    name: "propertiesByNames",
                    comment: "Description of FooBar's `propertiesByNames`.",
                    type: SwiftDictionary(value: SwiftPrimitive<String>()),
                    isOptional: true,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .static(value: "propertiesByNames")
                )
            ],
            conformance: [SwiftProtocol(name: "RUMDataModel", conformance: [codableProtocol])]
        )

        let printer = SwiftPrinter()
        let actual = try printer.print(swiftTypes: [`struct`])

        let expected = """

        /// Description of FooBar.
        public struct FooBar: RUMDataModel {
            /// Description of Bar.
            public let bar: BAR?

            /// Description of FooBar's `bizz`.
            public let bizz: Bizz = .case2

            /// Description of FooBar's `buzz`.
            public var buzz: [Buzz]?

            /// Description of FooBar's `propertiesByNames`.
            public let propertiesByNames: [String: String]?

            enum CodingKeys: String, CodingKey {
                case bar = "bar"
                case bizz = "bizz"
                case buzz = "buzz"
                case propertiesByNames = "propertiesByNames"
            }

            /// Description of Bar.
            public struct BAR: Codable {
                /// Description of Bar's `property1`.
                public let property1: String?

                /// Description of Bar's `property2`.
                public var property2: String

                enum CodingKeys: String, CodingKey {
                    case property1 = "property1"
                    case property2 = "property2"
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

        """

        XCTAssertEqual(expected, actual)
    }

    func testPrintingSwiftEnum() throws {
        let enumWithStringRawValue = SwiftEnum(
            name: "BizzBuzz",
            comment: nil,
            cases: [
                SwiftEnum.Case(label: "case1", rawValue: .string(value: "case 1")),
                SwiftEnum.Case(label: "case2", rawValue: .string(value: "case 2")),
                SwiftEnum.Case(label: "case3", rawValue: .string(value: "case 3")),
            ],
            conformance: [codableProtocol]
        )

        let enumWithIntegerRawValue = SwiftEnum(
            name: "FizzBazz",
            comment: nil,
            cases: [
                SwiftEnum.Case(label: "value1", rawValue: .integer(value: 1)),
                SwiftEnum.Case(label: "value2", rawValue: .integer(value: 2)),
                SwiftEnum.Case(label: "value3", rawValue: .integer(value: 3)),
            ],
            conformance: [codableProtocol]
        )

        let printer = SwiftPrinter()
        let actual = try printer.print(swiftTypes: [enumWithStringRawValue, enumWithIntegerRawValue])

        let expected = """

        public enum BizzBuzz: String, Codable {
            case case1 = "case 1"
            case case2 = "case 2"
            case case3 = "case 3"
        }

        public enum FizzBazz: Int, Codable {
            case value1 = 1
            case value2 = 2
            case value3 = 3
        }

        """

        XCTAssertEqual(expected, actual)
    }

    func testPrintingSwiftStructWithStaticCodingKeys() throws {
        let `struct` = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                SwiftStruct.Property(
                    name: "property1",
                    comment: nil,
                    type: SwiftPrimitive<String>(),
                    isOptional: false,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .static(value: "property_1")
                ),
                SwiftStruct.Property(
                    name: "property2",
                    comment: nil,
                    type: SwiftDictionary(
                        value: SwiftPrimitive<Int>()
                    ),
                    isOptional: false,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .static(value: "property_2")
                ),
            ],
            conformance: [codableProtocol]
        )

        let printer = SwiftPrinter()
        let actual = try printer.print(swiftTypes: [`struct`])

        let expected = """

        public struct Foo: Codable {
            public let property1: String

            public let property2: [String: Int]

            enum CodingKeys: String, CodingKey {
                case property1 = "property_1"
                case property2 = "property_2"
            }
        }

        """

        XCTAssertEqual(expected, actual)
    }

    func testPrintingSwiftStructWithDynamicCodingKeys() throws {
        let `struct` = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                SwiftStruct.Property(
                    name: "context",
                    comment: nil,
                    type: SwiftDictionary(
                        value: SwiftCodable()
                    ),
                    isOptional: false,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .dynamic
                ),
                SwiftStruct.Property(
                    name: "ignoredProperty",
                    comment: "This property will be ignored in coding because it uses default value and is immutable",
                    type: SwiftPrimitive<String>(),
                    isOptional: false,
                    mutability: .immutable,
                    defaultValue: "default value",
                    codingKey: .static(value: "ignoredProperty")
                )
            ],
            conformance: [codableProtocol]
        )

        let printer = SwiftPrinter()
        let actual = try printer.print(swiftTypes: [`struct`])

        let expected = """

        public struct Foo: Codable {
            public let context: [String: Codable]

            /// This property will be ignored in coding because it uses default value and is immutable
            public let ignoredProperty: String = "default value"

            enum StaticCodingKeys: String, CodingKey {
                case ignoredProperty = "ignoredProperty"
            }
        }

        extension Foo {
            public func encode(to encoder: Encoder) throws {
                // Encode dynamic properties:
                var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
                try context.forEach {
                    let key = DynamicCodingKey($0)
                    try dynamicContainer.encode(AnyEncodable($1), forKey: key)
                }
            }

            public init(from decoder: Decoder) throws {
                // Decode other properties into [String: Codable] dictionary:
                let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
                let dynamicKeys = dynamicContainer.allKeys
                var dictionary: [String: Codable] = [:]

                try dynamicKeys.forEach { codingKey in
                    dictionary[codingKey.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: codingKey)
                }

                self.context = dictionary
            }
        }

        """

        XCTAssertEqual(expected, actual)
    }

    func testPrintingSwiftStructWithStaticAndDynamicCodingKeys() throws {
        let `struct` = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                SwiftStruct.Property(
                    name: "property1",
                    comment: nil,
                    type: SwiftPrimitive<Int>(),
                    isOptional: false,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .static(value: "property_1")
                ),
                SwiftStruct.Property(
                    name: "context",
                    comment: nil,
                    type: SwiftDictionary(
                        value: SwiftEncodable()
                    ),
                    isOptional: false,
                    mutability: .mutableInternally,
                    defaultValue: nil,
                    codingKey: .dynamic
                ),
                SwiftStruct.Property(
                    name: "property2",
                    comment: nil,
                    type: SwiftPrimitive<Bool>(),
                    isOptional: true,
                    mutability: .mutable,
                    defaultValue: nil,
                    codingKey: .static(value: "property_2")
                )
            ],
            conformance: [codableProtocol]
        )

        let printer = SwiftPrinter()
        let actual = try printer.print(swiftTypes: [`struct`])

        let expected = """

        public struct Foo: Codable {
            public let property1: Int

            public internal(set) var context: [String: Encodable]

            public var property2: Bool?

            enum StaticCodingKeys: String, CodingKey {
                case property1 = "property_1"
                case property2 = "property_2"
            }
        }

        extension Foo {
            public func encode(to encoder: Encoder) throws {
                // Encode static properties:
                var staticContainer = encoder.container(keyedBy: StaticCodingKeys.self)
                try staticContainer.encodeIfPresent(property1, forKey: .property1)
                try staticContainer.encodeIfPresent(property2, forKey: .property2)

                // Encode dynamic properties:
                var dynamicContainer = encoder.container(keyedBy: DynamicCodingKey.self)
                try context.forEach {
                    let key = DynamicCodingKey($0)
                    try dynamicContainer.encode(AnyEncodable($1), forKey: key)
                }
            }

            public init(from decoder: Decoder) throws {
                // Decode static properties:
                let staticContainer = try decoder.container(keyedBy: StaticCodingKeys.self)
                self.property1 = try staticContainer.decode(Int.self, forKey: .property1)
                self.property2 = try staticContainer.decodeIfPresent(Bool.self, forKey: .property2)

                // Decode other properties into [String: Codable] dictionary:
                let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
                let allStaticKeys = Set(staticContainer.allKeys.map { $0.stringValue })
                let dynamicKeys = dynamicContainer.allKeys.filter { !allStaticKeys.contains($0.stringValue) }
                var dictionary: [String: Codable] = [:]

                try dynamicKeys.forEach { codingKey in
                    dictionary[codingKey.stringValue] = try dynamicContainer.decode(AnyCodable.self, forKey: codingKey)
                }

                self.context = dictionary
            }
        }

        """

        XCTAssertEqual(expected, actual)
    }

    func testPrintingSwiftStructWithAssociatedTypeEnum() throws {
        let `struct` = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                SwiftStruct.Property(
                    name: "fooProperty",
                    comment: nil,
                    type: SwiftPrimitive<Int>(),
                    isOptional: false,
                    mutability: .immutable,
                    defaultValue: nil,
                    codingKey: .static(value: "foo_property")
                ),
                SwiftStruct.Property(
                    name: "associatedTypeEnum",
                    comment: nil,
                    type: SwiftAssociatedTypeEnum(
                        name: "AssociatedTypeEnum",
                        comment: "`AssociatedTypeEnum` comment",
                        cases: [
                            SwiftAssociatedTypeEnum.Case(
                                label: "singleNumber",
                                associatedType: SwiftPrimitive<Int>()
                            ),
                            SwiftAssociatedTypeEnum.Case(
                                label: "multipleStrings",
                                associatedType: SwiftArray(element: SwiftPrimitive<String>())
                            ),
                            SwiftAssociatedTypeEnum.Case(
                                label: "someStruct",
                                associatedType: SwiftStruct(
                                    name: "SomeStruct",
                                    comment: "`SomeStruct` comment",
                                    properties: [
                                        SwiftStruct.Property(
                                            name: "someStructProperty",
                                            comment: nil,
                                            type: SwiftPrimitive<Bool>(),
                                            isOptional: false,
                                            mutability: .immutable,
                                            defaultValue: nil,
                                            codingKey: .static(value: "some_struct_property")
                                        )
                                    ],
                                    conformance: [codableProtocol]
                                )
                            )
                        ],
                        conformance: [codableProtocol]
                    ),
                    isOptional: true,
                    mutability: .mutable,
                    defaultValue: nil,
                    codingKey: .static(value: "associated_type_enum")
                )
            ],
            conformance: [codableProtocol]
        )

        let printer = SwiftPrinter()
        let actual = try printer.print(swiftTypes: [`struct`])

        let expected = """

        public struct Foo: Codable {
            public let fooProperty: Int

            public var associatedTypeEnum: AssociatedTypeEnum?

            enum CodingKeys: String, CodingKey {
                case fooProperty = "foo_property"
                case associatedTypeEnum = "associated_type_enum"
            }

            /// `AssociatedTypeEnum` comment
            public enum AssociatedTypeEnum: Codable {
                case singleNumber(value: Int)
                case multipleStrings(value: [String])
                case someStruct(value: SomeStruct)

                // MARK: - Codable

                public func encode(to encoder: Encoder) throws {
                    // Encode only the associated value, without encoding enum case
                    var container = encoder.singleValueContainer()

                    switch self {
                    case .singleNumber(let value):
                        try container.encode(value)
                    case .multipleStrings(let value):
                        try container.encode(value)
                    case .someStruct(let value):
                        try container.encode(value)
                    }
                }

                public init(from decoder: Decoder) throws {
                    // Decode enum case from associated value
                    let container = try decoder.singleValueContainer()

                    if let value = try? container.decode(Int.self) {
                        self = .singleNumber(value: value)
                        return
                    }
                    if let value = try? container.decode([String].self) {
                        self = .multipleStrings(value: value)
                        return
                    }
                    if let value = try? container.decode(SomeStruct.self) {
                        self = .someStruct(value: value)
                        return
                    }
                    let error = DecodingError.Context(
                        codingPath: container.codingPath,
                        debugDescription: \"\"\"
                        Failed to decode `AssociatedTypeEnum`.
                        Ran out of possibilities when trying to decode the value of associated type.
                        \"\"\"
                    )
                    throw DecodingError.typeMismatch(AssociatedTypeEnum.self, error)
                }

                /// `SomeStruct` comment
                public struct SomeStruct: Codable {
                    public let someStructProperty: Bool

                    enum CodingKeys: String, CodingKey {
                        case someStructProperty = "some_struct_property"
                    }
                }
            }
        }

        """

        XCTAssertEqual(expected, actual)
    }
}
