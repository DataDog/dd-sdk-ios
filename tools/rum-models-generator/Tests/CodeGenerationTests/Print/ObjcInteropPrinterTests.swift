/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import XCTest
@testable import CodeGeneration

final class ObjcInteropPrinterTests: XCTestCase {
    /// Prints Swift code along with its `@objc` interop code.
    private func printSwiftWithObjcInterop(for swiftTypes: [SwiftType]) throws -> String {
        let objcInteropTypes = try SwiftToObjcInteropTypeTransformer()
            .transform(swiftTypes: swiftTypes)

        let swiftPrinter = SwiftPrinter()
        let objcInteropPrinter = ObjcInteropPrinter(objcTypeNamesPrefix: "DD")

        return """
        // MARK: - Swift
        \(try swiftPrinter.print(swiftTypes: swiftTypes))
        // MARK: - ObjcInterop
        \(try objcInteropPrinter.print(objcInteropTypes: objcInteropTypes))
        """
    }

    // MARK: - Property wrappers for plain Swift values

    func testPrintingObjcInteropForSwiftStructWithStringProperties() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableString",
                    type: SwiftPrimitive<String>(),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableString",
                    type: SwiftPrimitive<String>(),
                    isOptional: true,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "mutableString",
                    type: SwiftPrimitive<String>(),
                    isOptional: false,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "optionalMutableString",
                    type: SwiftPrimitive<String>(),
                    isOptional: true,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableString: String

            public let optionalImmutableString: String?

            public var mutableString: String

            public var optionalMutableString: String?
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableString: String {
                root.swiftModel.immutableString
            }

            @objc public var optionalImmutableString: String? {
                root.swiftModel.optionalImmutableString
            }

            @objc public var mutableString: String {
                set { root.swiftModel.mutableString = newValue }
                get { root.swiftModel.mutableString }
            }

            @objc public var optionalMutableString: String? {
                set { root.swiftModel.optionalMutableString = newValue }
                get { root.swiftModel.optionalMutableString }
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructWithIntProperties() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableInt",
                    type: SwiftPrimitive<Int>(),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableInt",
                    type: SwiftPrimitive<Int>(),
                    isOptional: true,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "mutableInt",
                    type: SwiftPrimitive<Int>(),
                    isOptional: false,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "optionalMutableInt",
                    type: SwiftPrimitive<Int>(),
                    isOptional: true,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableInt: Int

            public let optionalImmutableInt: Int?

            public var mutableInt: Int

            public var optionalMutableInt: Int?
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableInt: NSNumber {
                root.swiftModel.immutableInt as NSNumber
            }

            @objc public var optionalImmutableInt: NSNumber? {
                root.swiftModel.optionalImmutableInt as NSNumber?
            }

            @objc public var mutableInt: NSNumber {
                set { root.swiftModel.mutableInt = newValue.intValue }
                get { root.swiftModel.mutableInt as NSNumber }
            }

            @objc public var optionalMutableInt: NSNumber? {
                set { root.swiftModel.optionalMutableInt = newValue?.intValue }
                get { root.swiftModel.optionalMutableInt as NSNumber? }
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructWithInt64Properties() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableInt64",
                    type: SwiftPrimitive<Int64>(),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableInt64",
                    type: SwiftPrimitive<Int64>(),
                    isOptional: true,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "mutableInt",
                    type: SwiftPrimitive<Int64>(),
                    isOptional: false,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "optionalMutableInt64",
                    type: SwiftPrimitive<Int64>(),
                    isOptional: true,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableInt64: Int64

            public let optionalImmutableInt64: Int64?

            public var mutableInt: Int64

            public var optionalMutableInt64: Int64?
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableInt64: NSNumber {
                root.swiftModel.immutableInt64 as NSNumber
            }

            @objc public var optionalImmutableInt64: NSNumber? {
                root.swiftModel.optionalImmutableInt64 as NSNumber?
            }

            @objc public var mutableInt: NSNumber {
                set { root.swiftModel.mutableInt = newValue.int64Value }
                get { root.swiftModel.mutableInt as NSNumber }
            }

            @objc public var optionalMutableInt64: NSNumber? {
                set { root.swiftModel.optionalMutableInt64 = newValue?.int64Value }
                get { root.swiftModel.optionalMutableInt64 as NSNumber? }
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructWithDoubleProperties() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableDouble",
                    type: SwiftPrimitive<Double>(),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableDouble",
                    type: SwiftPrimitive<Double>(),
                    isOptional: true,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "mutableDouble",
                    type: SwiftPrimitive<Double>(),
                    isOptional: false,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "optionalMutableDouble",
                    type: SwiftPrimitive<Double>(),
                    isOptional: true,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableDouble: Double

            public let optionalImmutableDouble: Double?

            public var mutableDouble: Double

            public var optionalMutableDouble: Double?
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableDouble: NSNumber {
                root.swiftModel.immutableDouble as NSNumber
            }

            @objc public var optionalImmutableDouble: NSNumber? {
                root.swiftModel.optionalImmutableDouble as NSNumber?
            }

            @objc public var mutableDouble: NSNumber {
                set { root.swiftModel.mutableDouble = newValue.doubleValue }
                get { root.swiftModel.mutableDouble as NSNumber }
            }

            @objc public var optionalMutableDouble: NSNumber? {
                set { root.swiftModel.optionalMutableDouble = newValue?.doubleValue }
                get { root.swiftModel.optionalMutableDouble as NSNumber? }
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructWithBoolProperties() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableBool",
                    type: SwiftPrimitive<Bool>(),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableBool",
                    type: SwiftPrimitive<Bool>(),
                    isOptional: true,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "mutableBool",
                    type: SwiftPrimitive<Bool>(),
                    isOptional: false,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "optionalMutableBool",
                    type: SwiftPrimitive<Bool>(),
                    isOptional: true,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableBool: Bool

            public let optionalImmutableBool: Bool?

            public var mutableBool: Bool

            public var optionalMutableBool: Bool?
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableBool: NSNumber {
                root.swiftModel.immutableBool as NSNumber
            }

            @objc public var optionalImmutableBool: NSNumber? {
                root.swiftModel.optionalImmutableBool as NSNumber?
            }

            @objc public var mutableBool: NSNumber {
                set { root.swiftModel.mutableBool = newValue.boolValue }
                get { root.swiftModel.mutableBool as NSNumber }
            }

            @objc public var optionalMutableBool: NSNumber? {
                set { root.swiftModel.optionalMutableBool = newValue?.boolValue }
                get { root.swiftModel.optionalMutableBool as NSNumber? }
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructWithEnumProperties() throws {
        func mockEnumeration(named name: String) -> SwiftEnum {
            return SwiftEnum(
                name: name,
                comment: nil,
                cases: [
                    SwiftEnum.Case(label: "case1", rawValue: .string(value: "case1")),
                    SwiftEnum.Case(label: "case2", rawValue: .string(value: "case2")),
                    SwiftEnum.Case(label: "case3", rawValue: .string(value: "case3")),
                ],
                conformance: []
            )
        }

        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableEnum",
                    type: mockEnumeration(named: "Enumeration1"),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableEnum",
                    type: mockEnumeration(named: "Enumeration2"),
                    isOptional: true,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "mutableEnum",
                    type: mockEnumeration(named: "Enumeration3"),
                    isOptional: false,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "optionalMutableEnum",
                    type: mockEnumeration(named: "Enumeration4"),
                    isOptional: true,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableEnum: Enumeration1

            public let optionalImmutableEnum: Enumeration2?

            public var mutableEnum: Enumeration3

            public var optionalMutableEnum: Enumeration4?

            public enum Enumeration1: String {
                case case1 = "case1"
                case case2 = "case2"
                case case3 = "case3"
            }

            public enum Enumeration2: String {
                case case1 = "case1"
                case case2 = "case2"
                case case3 = "case3"
            }

            public enum Enumeration3: String {
                case case1 = "case1"
                case case2 = "case2"
                case case3 = "case3"
            }

            public enum Enumeration4: String {
                case case1 = "case1"
                case case2 = "case2"
                case case3 = "case3"
            }
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableEnum: DDFooEnumeration1 {
                .init(swift: root.swiftModel.immutableEnum)
            }

            @objc public var optionalImmutableEnum: DDFooEnumeration2 {
                .init(swift: root.swiftModel.optionalImmutableEnum)
            }

            @objc public var mutableEnum: DDFooEnumeration3 {
                set { root.swiftModel.mutableEnum = newValue.toSwift }
                get { .init(swift: root.swiftModel.mutableEnum) }
            }

            @objc public var optionalMutableEnum: DDFooEnumeration4 {
                set { root.swiftModel.optionalMutableEnum = newValue.toSwift }
                get { .init(swift: root.swiftModel.optionalMutableEnum) }
            }
        }

        @objc
        public enum DDFooEnumeration1: Int {
            internal init(swift: Foo.Enumeration1) {
                switch swift {
                case .case1: self = .case1
                case .case2: self = .case2
                case .case3: self = .case3
                }
            }

            internal var toSwift: Foo.Enumeration1 {
                switch self {
                case .case1: return .case1
                case .case2: return .case2
                case .case3: return .case3
                }
            }

            case case1
            case case2
            case case3
        }

        @objc
        public enum DDFooEnumeration2: Int {
            internal init(swift: Foo.Enumeration2?) {
                switch swift {
                case nil: self = .none
                case .case1?: self = .case1
                case .case2?: self = .case2
                case .case3?: self = .case3
                }
            }

            internal var toSwift: Foo.Enumeration2? {
                switch self {
                case .none: return nil
                case .case1: return .case1
                case .case2: return .case2
                case .case3: return .case3
                }
            }

            case none
            case case1
            case case2
            case case3
        }

        @objc
        public enum DDFooEnumeration3: Int {
            internal init(swift: Foo.Enumeration3) {
                switch swift {
                case .case1: self = .case1
                case .case2: self = .case2
                case .case3: self = .case3
                }
            }

            internal var toSwift: Foo.Enumeration3 {
                switch self {
                case .case1: return .case1
                case .case2: return .case2
                case .case3: return .case3
                }
            }

            case case1
            case case2
            case case3
        }

        @objc
        public enum DDFooEnumeration4: Int {
            internal init(swift: Foo.Enumeration4?) {
                switch swift {
                case nil: self = .none
                case .case1?: self = .case1
                case .case2?: self = .case2
                case .case3?: self = .case3
                }
            }

            internal var toSwift: Foo.Enumeration4? {
                switch self {
                case .none: return nil
                case .case1: return .case1
                case .case2: return .case2
                case .case3: return .case3
                }
            }

            case none
            case case1
            case case2
            case case3
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    // MARK: - Property wrappers for Swift arrays

    func testPrintingObjcInteropForSwiftStructWithStringArrayProperties() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableStrings",
                    type: SwiftArray(element: SwiftPrimitive<String>()),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableStrings",
                    type: SwiftArray(element: SwiftPrimitive<String>()),
                    isOptional: true,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "mutableStrings",
                    type: SwiftArray(element: SwiftPrimitive<String>()),
                    isOptional: false,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "optionalMutableStrings",
                    type: SwiftArray(element: SwiftPrimitive<String>()),
                    isOptional: true,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableStrings: [String]

            public let optionalImmutableStrings: [String]?

            public var mutableStrings: [String]

            public var optionalMutableStrings: [String]?
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableStrings: [String] {
                root.swiftModel.immutableStrings
            }

            @objc public var optionalImmutableStrings: [String]? {
                root.swiftModel.optionalImmutableStrings
            }

            @objc public var mutableStrings: [String] {
                set { root.swiftModel.mutableStrings = newValue }
                get { root.swiftModel.mutableStrings }
            }

            @objc public var optionalMutableStrings: [String]? {
                set { root.swiftModel.optionalMutableStrings = newValue }
                get { root.swiftModel.optionalMutableStrings }
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructWithInt64ArrayProperties() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableInt64s",
                    type: SwiftArray(element: SwiftPrimitive<Int64>()),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableInt64s",
                    type: SwiftArray(element: SwiftPrimitive<Int64>()),
                    isOptional: true,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "mutableInt64s",
                    type: SwiftArray(element: SwiftPrimitive<Int64>()),
                    isOptional: false,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "optionalMutableInt64s",
                    type: SwiftArray(element: SwiftPrimitive<Int64>()),
                    isOptional: true,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableInt64s: [Int64]

            public let optionalImmutableInt64s: [Int64]?

            public var mutableInt64s: [Int64]

            public var optionalMutableInt64s: [Int64]?
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableInt64s: [NSNumber] {
                root.swiftModel.immutableInt64s as [NSNumber]
            }

            @objc public var optionalImmutableInt64s: [NSNumber]? {
                root.swiftModel.optionalImmutableInt64s as [NSNumber]?
            }

            @objc public var mutableInt64s: [NSNumber] {
                set { root.swiftModel.mutableInt64s = newValue.map { $0.int64Value } }
                get { root.swiftModel.mutableInt64s as [NSNumber] }
            }

            @objc public var optionalMutableInt64s: [NSNumber]? {
                set { root.swiftModel.optionalMutableInt64s = newValue?.map { $0.int64Value } }
                get { root.swiftModel.optionalMutableInt64s as [NSNumber]? }
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructWithEnumArrayProperties() throws {
        func mockEnumeration(named name: String) -> SwiftEnum {
            return SwiftEnum(
                name: name,
                comment: nil,
                cases: [
                    SwiftEnum.Case(label: "option1", rawValue: .string(value: "option1")),
                    SwiftEnum.Case(label: "option2", rawValue: .string(value: "option2")),
                    SwiftEnum.Case(label: "option3", rawValue: .string(value: "option3")),
                ],
                conformance: []
            )
        }

        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableEnums",
                    type: SwiftArray(element: mockEnumeration(named: "Options1")),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableEnums",
                    type: SwiftArray(element: mockEnumeration(named: "Options2")),
                    isOptional: true,
                    mutability: .immutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableEnums: [Options1]

            public let optionalImmutableEnums: [Options2]?

            public enum Options1: String {
                case option1 = "option1"
                case option2 = "option2"
                case option3 = "option3"
            }

            public enum Options2: String {
                case option1 = "option1"
                case option2 = "option2"
                case option3 = "option3"
            }
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableEnums: [Int] {
                root.swiftModel.immutableEnums.map { DDFooOptions1(swift: $0).rawValue }
            }

            @objc public var optionalImmutableEnums: [Int]? {
                root.swiftModel.optionalImmutableEnums?.map { DDFooOptions2(swift: $0).rawValue }
            }
        }

        @objc
        public enum DDFooOptions1: Int {
            internal init(swift: Foo.Options1) {
                switch swift {
                case .option1: self = .option1
                case .option2: self = .option2
                case .option3: self = .option3
                }
            }

            internal var toSwift: Foo.Options1 {
                switch self {
                case .option1: return .option1
                case .option2: return .option2
                case .option3: return .option3
                }
            }

            case option1
            case option2
            case option3
        }

        @objc
        public enum DDFooOptions2: Int {
            internal init(swift: Foo.Options2?) {
                switch swift {
                case nil: self = .none
                case .option1?: self = .option1
                case .option2?: self = .option2
                case .option3?: self = .option3
                }
            }

            internal var toSwift: Foo.Options2? {
                switch self {
                case .none: return nil
                case .option1: return .option1
                case .option2: return .option2
                case .option3: return .option3
                }
            }

            case none
            case option1
            case option2
            case option3
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructWithStructArrayProperties() throws {
        func mockStruct(named name: String) -> SwiftStruct {
            return SwiftStruct(
                name: name,
                comment: nil,
                properties: [
                    SwiftStruct.Property(
                        name: "property",
                        comment: nil,
                        type: SwiftPrimitive<String>(),
                        isOptional: false,
                        mutability: .immutable,
                        defaultValue: nil,
                        codingKey: .static(value: "property")
                    )
                ],
                conformance: []
            )
        }

        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableStructs",
                    type: SwiftArray(element: mockStruct(named: "Bar")),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableStructs",
                    type: SwiftArray(element: mockStruct(named: "Bizz")),
                    isOptional: true,
                    mutability: .immutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableStructs: [Bar]

            public let optionalImmutableStructs: [Bizz]?

            public struct Bar {
                public let property: String
            }

            public struct Bizz {
                public let property: String
            }
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableStructs: [DDFooBar] {
                root.swiftModel.immutableStructs.map { DDFooBar(swiftModel: $0) }
            }

            @objc public var optionalImmutableStructs: [DDFooBizz]? {
                root.swiftModel.optionalImmutableStructs?.map { DDFooBizz(swiftModel: $0) }
            }
        }

        @objc
        public class DDFooBar: NSObject {
            internal var swiftModel: Foo.Bar
            internal var root: DDFooBar { self }

            internal init(swiftModel: Foo.Bar) {
                self.swiftModel = swiftModel
            }

            @objc public var property: String {
                root.swiftModel.property
            }
        }

        @objc
        public class DDFooBizz: NSObject {
            internal var swiftModel: Foo.Bizz
            internal var root: DDFooBizz { self }

            internal init(swiftModel: Foo.Bizz) {
                self.swiftModel = swiftModel
            }

            @objc public var property: String {
                root.swiftModel.property
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    // MARK: - Property wrappers for Swift Dictionaries

    func testPrintingObjcInteropForSwiftStructWithStringDictionaryProperties() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableStrings",
                    type: SwiftDictionary(value: SwiftPrimitive<String>()),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableStrings",
                    type: SwiftDictionary(value: SwiftPrimitive<String>()),
                    isOptional: true,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "mutableStrings",
                    type: SwiftDictionary(value: SwiftPrimitive<String>()),
                    isOptional: false,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "optionalMutableStrings",
                    type: SwiftDictionary(value: SwiftPrimitive<String>()),
                    isOptional: true,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableStrings: [String: String]

            public let optionalImmutableStrings: [String: String]?

            public var mutableStrings: [String: String]

            public var optionalMutableStrings: [String: String]?
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableStrings: [String: String] {
                root.swiftModel.immutableStrings
            }

            @objc public var optionalImmutableStrings: [String: String]? {
                root.swiftModel.optionalImmutableStrings
            }

            @objc public var mutableStrings: [String: String] {
                set { root.swiftModel.mutableStrings = newValue }
                get { root.swiftModel.mutableStrings }
            }

            @objc public var optionalMutableStrings: [String: String]? {
                set { root.swiftModel.optionalMutableStrings = newValue }
                get { root.swiftModel.optionalMutableStrings }
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructWithInt64DictionaryProperties() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableInt64s",
                    type: SwiftDictionary(value: SwiftPrimitive<Int64>()),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableInt64s",
                    type: SwiftDictionary(value: SwiftPrimitive<Int64>()),
                    isOptional: true,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "mutableInt64s",
                    type: SwiftDictionary(value: SwiftPrimitive<Int64>()),
                    isOptional: false,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "optionalMutableInt64s",
                    type: SwiftDictionary(value: SwiftPrimitive<Int64>()),
                    isOptional: true,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableInt64s: [String: Int64]

            public let optionalImmutableInt64s: [String: Int64]?

            public var mutableInt64s: [String: Int64]

            public var optionalMutableInt64s: [String: Int64]?
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableInt64s: [String: NSNumber] {
                root.swiftModel.immutableInt64s as [String: NSNumber]
            }

            @objc public var optionalImmutableInt64s: [String: NSNumber]? {
                root.swiftModel.optionalImmutableInt64s as [String: NSNumber]?
            }

            @objc public var mutableInt64s: [String: NSNumber] {
                set { root.swiftModel.mutableInt64s = newValue.reduce(into: [:]) { $0[$1.0] = $1.1.int64Value }
                get { root.swiftModel.mutableInt64s as [String: NSNumber] }
            }

            @objc public var optionalMutableInt64s: [String: NSNumber]? {
                set { root.swiftModel.optionalMutableInt64s = newValue?.reduce(into: [:]) { $0[$1.0] = $1.1.int64Value }
                get { root.swiftModel.optionalMutableInt64s as [String: NSNumber]? }
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructWithCodableDictionaryProperties() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "immutableCodables",
                    type: SwiftDictionary(value: SwiftCodable()),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalImmutableCodables",
                    type: SwiftDictionary(value: SwiftCodable()),
                    isOptional: true,
                    mutability: .immutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public let immutableCodables: [String: Codable]

            public let optionalImmutableCodables: [String: Codable]?
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var immutableCodables: [String: Any] {
                root.swiftModel.immutableCodables.dd.objCAttributes
            }

            @objc public var optionalImmutableCodables: [String: Any]? {
                root.swiftModel.optionalImmutableCodables?.dd.objCAttributes
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    // MARK: - Nested Swift Structs and Enums

    func testPrintingObjcInteropForSwiftStructWithNestedStructs() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "mutableBar",
                    type: SwiftStruct(
                        name: "MutableBar",
                        comment: nil,
                        properties: [
                            .mock(propertyName: "immutableString", type: SwiftPrimitive<String>(), isOptional: false, mutability: .immutable),
                            .mock(propertyName: "optionalImmutableString", type: SwiftPrimitive<String>(), isOptional: true, mutability: .immutable),
                            .mock(propertyName: "mutableString", type: SwiftPrimitive<String>(), isOptional: false, mutability: .mutable),
                            .mock(propertyName: "optionalMutableString", type: SwiftPrimitive<String>(), isOptional: true, mutability: .mutable),
                        ],
                        conformance: []
                    ),
                    isOptional: false,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "immutableBar",
                    type: SwiftStruct(
                        name: "ImmutableBar",
                        comment: nil,
                        properties: [
                            .mock(propertyName: "immutableString", type: SwiftPrimitive<String>(), isOptional: false, mutability: .immutable),
                            .mock(propertyName: "optionalImmutableString", type: SwiftPrimitive<String>(), isOptional: true, mutability: .immutable),
                        ],
                        conformance: []
                    ),
                    isOptional: false,
                    mutability: .immutable
                ),
                .mock(
                    propertyName: "optionalMutableBar",
                    type: SwiftStruct(
                        name: "OptionalMutableBar",
                        comment: nil,
                        properties: [
                            .mock(propertyName: "immutableString", type: SwiftPrimitive<String>(), isOptional: false, mutability: .immutable),
                            .mock(propertyName: "optionalImmutableString", type: SwiftPrimitive<String>(), isOptional: true, mutability: .immutable),
                        ],
                        conformance: []
                    ),
                    isOptional: true,
                    mutability: .mutable
                ),
                .mock(
                    propertyName: "optionalImmutableBar",
                    type: SwiftStruct(
                        name: "OptionalImmutableBar",
                        comment: nil,
                        properties: [
                            .mock(propertyName: "immutableString", type: SwiftPrimitive<String>(), isOptional: false, mutability: .immutable),
                            .mock(propertyName: "optionalImmutableString", type: SwiftPrimitive<String>(), isOptional: true, mutability: .immutable),
                        ],
                        conformance: []
                    ),
                    isOptional: true,
                    mutability: .immutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public var mutableBar: MutableBar

            public let immutableBar: ImmutableBar

            public var optionalMutableBar: OptionalMutableBar?

            public let optionalImmutableBar: OptionalImmutableBar?

            public struct MutableBar {
                public let immutableString: String

                public let optionalImmutableString: String?

                public var mutableString: String

                public var optionalMutableString: String?
            }

            public struct ImmutableBar {
                public let immutableString: String

                public let optionalImmutableString: String?
            }

            public struct OptionalMutableBar {
                public let immutableString: String

                public let optionalImmutableString: String?
            }

            public struct OptionalImmutableBar {
                public let immutableString: String

                public let optionalImmutableString: String?
            }
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var mutableBar: DDFooMutableBar {
                DDFooMutableBar(root: root)
            }

            @objc public var immutableBar: DDFooImmutableBar {
                DDFooImmutableBar(root: root)
            }

            @objc public var optionalMutableBar: DDFooOptionalMutableBar? {
                root.swiftModel.optionalMutableBar != nil ? DDFooOptionalMutableBar(root: root) : nil
            }

            @objc public var optionalImmutableBar: DDFooOptionalImmutableBar? {
                root.swiftModel.optionalImmutableBar != nil ? DDFooOptionalImmutableBar(root: root) : nil
            }
        }

        @objc
        public class DDFooMutableBar: NSObject {
            internal let root: DDFoo

            internal init(root: DDFoo) {
                self.root = root
            }

            @objc public var immutableString: String {
                root.swiftModel.mutableBar.immutableString
            }

            @objc public var optionalImmutableString: String? {
                root.swiftModel.mutableBar.optionalImmutableString
            }

            @objc public var mutableString: String {
                set { root.swiftModel.mutableBar.mutableString = newValue }
                get { root.swiftModel.mutableBar.mutableString }
            }

            @objc public var optionalMutableString: String? {
                set { root.swiftModel.mutableBar.optionalMutableString = newValue }
                get { root.swiftModel.mutableBar.optionalMutableString }
            }
        }

        @objc
        public class DDFooImmutableBar: NSObject {
            internal let root: DDFoo

            internal init(root: DDFoo) {
                self.root = root
            }

            @objc public var immutableString: String {
                root.swiftModel.immutableBar.immutableString
            }

            @objc public var optionalImmutableString: String? {
                root.swiftModel.immutableBar.optionalImmutableString
            }
        }

        @objc
        public class DDFooOptionalMutableBar: NSObject {
            internal let root: DDFoo

            internal init(root: DDFoo) {
                self.root = root
            }

            @objc public var immutableString: String {
                root.swiftModel.optionalMutableBar!.immutableString
            }

            @objc public var optionalImmutableString: String? {
                root.swiftModel.optionalMutableBar!.optionalImmutableString
            }
        }

        @objc
        public class DDFooOptionalImmutableBar: NSObject {
            internal let root: DDFoo

            internal init(root: DDFoo) {
                self.root = root
            }

            @objc public var immutableString: String {
                root.swiftModel.optionalImmutableBar!.immutableString
            }

            @objc public var optionalImmutableString: String? {
                root.swiftModel.optionalImmutableBar!.optionalImmutableString
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructWithNestedEnum() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "bar",
                    type: SwiftStruct(
                        name: "Bar",
                        comment: nil,
                        properties: [
                            .mock(
                                propertyName: "enumeration",
                                type: SwiftEnum(
                                    name: "Enumeration",
                                    comment: nil,
                                    cases: [
                                        SwiftEnum.Case(label: "case1", rawValue: .string(value: "case1")),
                                        SwiftEnum.Case(label: "case2", rawValue: .string(value: "case2")),
                                        SwiftEnum.Case(label: "case3", rawValue: .string(value: "case3")),
                                    ],
                                    conformance: []
                                ),
                                isOptional: false,
                                mutability: .mutable
                            ),
                        ],
                        conformance: []
                    ),
                    isOptional: false,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public var bar: Bar

            public struct Bar {
                public var enumeration: Enumeration

                public enum Enumeration: String {
                    case case1 = "case1"
                    case case2 = "case2"
                    case case3 = "case3"
                }
            }
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var bar: DDFooBar {
                DDFooBar(root: root)
            }
        }

        @objc
        public class DDFooBar: NSObject {
            internal let root: DDFoo

            internal init(root: DDFoo) {
                self.root = root
            }

            @objc public var enumeration: DDFooBarEnumeration {
                set { root.swiftModel.bar.enumeration = newValue.toSwift }
                get { .init(swift: root.swiftModel.bar.enumeration) }
            }
        }

        @objc
        public enum DDFooBarEnumeration: Int {
            internal init(swift: Foo.Bar.Enumeration) {
                switch swift {
                case .case1: self = .case1
                case .case2: self = .case2
                case .case3: self = .case3
                }
            }

            internal var toSwift: Foo.Bar.Enumeration {
                switch self {
                case .case1: return .case1
                case .case2: return .case2
                case .case3: return .case3
                }
            }

            case case1
            case case2
            case case3
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct])

        XCTAssertEqual(expected, actual)
    }

    // MARK: - Referenced Swift Structs and Enums

    func testPrintingObjcInteropForSwiftStructsWithReferencedStructAndEnum() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "bar",
                    type: SwiftStruct(
                        name: "Bar",
                        comment: nil,
                        properties: [
                            .mock(
                                propertyName: "sharedStruct",
                                type: SwiftTypeReference(referencedTypeName: "SharedStruct"),
                                isOptional: false,
                                mutability: .mutable
                            ),
                            .mock(
                                propertyName: "sharedEnumeration",
                                type: SwiftTypeReference(referencedTypeName: "SharedEnum"),
                                isOptional: false,
                                mutability: .mutable
                            ),
                        ],
                        conformance: []
                    ),
                    isOptional: false,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let bizzStruct = SwiftStruct(
            name: "Bizz",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "buzz",
                    type: SwiftStruct(
                        name: "Buzz",
                        comment: nil,
                        properties: [
                            .mock(
                                propertyName: "sharedStruct",
                                type: SwiftTypeReference(referencedTypeName: "SharedStruct"),
                                isOptional: false,
                                mutability: .mutable
                            ),
                            .mock(
                                propertyName: "sharedEnumeration",
                                type: SwiftTypeReference(referencedTypeName: "SharedEnum"),
                                isOptional: false,
                                mutability: .mutable
                            ),
                        ],
                        conformance: []
                    ),
                    isOptional: false,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let sharedStruct = SwiftStruct(
            name: "SharedStruct",
            comment: nil,
            properties: [
                .mock(propertyName: "integer", type: SwiftPrimitive<Int>(), isOptional: true, mutability: .mutable)
            ],
            conformance: []
        )

        let sharedEnum = SwiftEnum(
            name: "SharedEnum",
            comment: nil,
            cases: [
                SwiftEnum.Case(label: "case1", rawValue: .string(value: "case1")),
                SwiftEnum.Case(label: "case2", rawValue: .string(value: "case2")),
                SwiftEnum.Case(label: "case3", rawValue: .string(value: "case3")),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public var bar: Bar

            public struct Bar {
                public var sharedStruct: SharedStruct

                public var sharedEnumeration: SharedEnum
            }
        }

        public struct Bizz {
            public var buzz: Buzz

            public struct Buzz {
                public var sharedStruct: SharedStruct

                public var sharedEnumeration: SharedEnum
            }
        }

        public struct SharedStruct {
            public var integer: Int?
        }

        public enum SharedEnum: String {
            case case1 = "case1"
            case case2 = "case2"
            case case3 = "case3"
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var bar: DDFooBar {
                DDFooBar(root: root)
            }
        }

        @objc
        public class DDFooBar: NSObject {
            internal let root: DDFoo

            internal init(root: DDFoo) {
                self.root = root
            }

            @objc public var sharedStruct: DDFooBarSharedStruct {
                DDFooBarSharedStruct(root: root)
            }

            @objc public var sharedEnumeration: DDFooBarSharedEnum {
                set { root.swiftModel.bar.sharedEnumeration = newValue.toSwift }
                get { .init(swift: root.swiftModel.bar.sharedEnumeration) }
            }
        }

        @objc
        public class DDFooBarSharedStruct: NSObject {
            internal let root: DDFoo

            internal init(root: DDFoo) {
                self.root = root
            }

            @objc public var integer: NSNumber? {
                set { root.swiftModel.bar.sharedStruct.integer = newValue?.intValue }
                get { root.swiftModel.bar.sharedStruct.integer as NSNumber? }
            }
        }

        @objc
        public enum DDFooBarSharedEnum: Int {
            internal init(swift: SharedEnum) {
                switch swift {
                case .case1: self = .case1
                case .case2: self = .case2
                case .case3: self = .case3
                }
            }

            internal var toSwift: SharedEnum {
                switch self {
                case .case1: return .case1
                case .case2: return .case2
                case .case3: return .case3
                }
            }

            case case1
            case case2
            case case3
        }

        @objc
        public class DDBizz: NSObject {
            internal var swiftModel: Bizz
            internal var root: DDBizz { self }

            internal init(swiftModel: Bizz) {
                self.swiftModel = swiftModel
            }

            @objc public var buzz: DDBizzBuzz {
                DDBizzBuzz(root: root)
            }
        }

        @objc
        public class DDBizzBuzz: NSObject {
            internal let root: DDBizz

            internal init(root: DDBizz) {
                self.root = root
            }

            @objc public var sharedStruct: DDBizzBuzzSharedStruct {
                DDBizzBuzzSharedStruct(root: root)
            }

            @objc public var sharedEnumeration: DDBizzBuzzSharedEnum {
                set { root.swiftModel.buzz.sharedEnumeration = newValue.toSwift }
                get { .init(swift: root.swiftModel.buzz.sharedEnumeration) }
            }
        }

        @objc
        public class DDBizzBuzzSharedStruct: NSObject {
            internal let root: DDBizz

            internal init(root: DDBizz) {
                self.root = root
            }

            @objc public var integer: NSNumber? {
                set { root.swiftModel.buzz.sharedStruct.integer = newValue?.intValue }
                get { root.swiftModel.buzz.sharedStruct.integer as NSNumber? }
            }
        }

        @objc
        public enum DDBizzBuzzSharedEnum: Int {
            internal init(swift: SharedEnum) {
                switch swift {
                case .case1: self = .case1
                case .case2: self = .case2
                case .case3: self = .case3
                }
            }

            internal var toSwift: SharedEnum {
                switch self {
                case .case1: return .case1
                case .case2: return .case2
                case .case3: return .case3
                }
            }

            case case1
            case case2
            case case3
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct, bizzStruct, sharedStruct, sharedEnum])

        XCTAssertEqual(expected, actual)
    }

    func testPrintingObjcInteropForSwiftStructsWithReferencedAssociatedTypeEnum() throws {
        let fooStruct = SwiftStruct(
            name: "Foo",
            comment: nil,
            properties: [
                .mock(
                    propertyName: "bar",
                    type: SwiftStruct(
                        name: "Bar",
                        comment: nil,
                        properties: [
                            .mock(
                                propertyName: "sharedEnumeration",
                                type: SwiftTypeReference(referencedTypeName: "SharedAssociatedTypeEnum"),
                                isOptional: false,
                                mutability: .immutable
                            ),
                        ],
                        conformance: []
                    ),
                    isOptional: false,
                    mutability: .mutable
                ),
            ],
            conformance: []
        )

        let sharedAssociatedTypeEnum = SwiftAssociatedTypeEnum(
            name: "SharedAssociatedTypeEnum",
            comment: nil,
            cases: [
                SwiftAssociatedTypeEnum.Case(label: "singleNumber", associatedType: SwiftPrimitive<Int>()),
                SwiftAssociatedTypeEnum.Case(label: "multipleNumbers", associatedType: SwiftArray(element: SwiftPrimitive<Int>())),
                SwiftAssociatedTypeEnum.Case(label: "mapOfNumbers", associatedType: SwiftDictionary(value: SwiftPrimitive<Int>())),
            ],
            conformance: []
        )

        let expected = """
        // MARK: - Swift

        public struct Foo {
            public var bar: Bar

            public struct Bar {
                public let sharedEnumeration: SharedAssociatedTypeEnum
            }
        }

        public enum SharedAssociatedTypeEnum {
            case singleNumber(value: Int)
            case multipleNumbers(value: [Int])
            case mapOfNumbers(value: [String: Int])
        }

        // MARK: - ObjcInterop

        @objc
        public class DDFoo: NSObject {
            internal var swiftModel: Foo
            internal var root: DDFoo { self }

            internal init(swiftModel: Foo) {
                self.swiftModel = swiftModel
            }

            @objc public var bar: DDFooBar {
                DDFooBar(root: root)
            }
        }

        @objc
        public class DDFooBar: NSObject {
            internal let root: DDFoo

            internal init(root: DDFoo) {
                self.root = root
            }

            @objc public var sharedEnumeration: DDFooBarSharedAssociatedTypeEnum {
                DDFooBarSharedAssociatedTypeEnum(root: root)
            }
        }

        @objc
        public class DDFooBarSharedAssociatedTypeEnum: NSObject {
            internal let root: DDFoo

            internal init(root: DDFoo) {
                self.root = root
            }

            @objc public var singleNumber: NSNumber? {
                guard case .singleNumber(let value) = root.swiftModel.bar.sharedEnumeration else {
                    return nil
                }
                return value as NSNumber
            }

            @objc public var multipleNumbers: [NSNumber]? {
                guard case .multipleNumbers(let value) = root.swiftModel.bar.sharedEnumeration else {
                    return nil
                }
                return value as [NSNumber]
            }

            @objc public var mapOfNumbers: [String: NSNumber]? {
                guard case .mapOfNumbers(let value) = root.swiftModel.bar.sharedEnumeration else {
                    return nil
                }
                return value as [String: NSNumber]
            }
        }

        """

        let actual = try printSwiftWithObjcInterop(for: [fooStruct, sharedAssociatedTypeEnum])

        XCTAssertEqual(expected, actual)
    }
}

extension SwiftStruct.Property {
    static func mock(
        propertyName: String,
        type: SwiftType,
        isOptional: Bool,
        mutability: SwiftStruct.Property.Mutability
    ) -> SwiftStruct.Property {
        return SwiftStruct.Property(
            name: propertyName,
            comment: nil,
            type: type,
            isOptional: isOptional,
            mutability: mutability,
            defaultValue: nil,
            codingKey: .static(value: propertyName)
        )
    }
}
