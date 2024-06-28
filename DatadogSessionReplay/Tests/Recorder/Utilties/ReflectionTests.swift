/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
import TestUtilities

@testable import DatadogSessionReplay

class ReflectionTests: XCTestCase {
    func testClassReflection() {
        class Parent {
            let property1: Int
            let property2: String

            init(property1: Int, property2: String) {
                self.property1 = property1
                self.property2 = property2
            }
        }

        class Subclass: Parent {
            let property3: Bool

            init(property1: Int, property2: String, property3: Bool) {
                self.property3 = property3
                super.init(property1: property1, property2: property2)
            }
        }

        let ref = Subclass(
            property1: .mockRandom(),
            property2: .mockRandom(),
            property3: .mockRandom()
        )

        let mirror = Mirror(reflecting: ref)
        XCTAssertEqual(try mirror.descendant(path: "property1"), ref.property1)
        XCTAssertEqual(try mirror.descendant(path: "property2"), ref.property2)
        XCTAssertEqual(try mirror.descendant(path: "property3"), ref.property3)
        XCTAssertThrowsError(try mirror.descendant(String.self, path: "property4"))
    }

    func testStructReflection() {
        struct Value {
            let property1: Int?
            let property2: String?
            let property3: Bool?
        }

        let value = Value(
            property1: .mockRandom(),
            property2: .mockRandom(),
            property3: .mockRandom()
        )

        let mirror = Mirror(reflecting: value)
        XCTAssertEqual(try mirror.descendant(path: "property1"), value.property1)
        XCTAssertEqual(try mirror.descendant(path: "property2"), value.property2)
        XCTAssertEqual(try mirror.descendant(path: "property3"), value.property3)
        XCTAssertThrowsError(try mirror.descendant(String.self, path: "property4"))
    }

    func testTupleReflection() {
        typealias Tuple = (Int?, String?, Bool?)

        let tuple = Tuple(
            .mockRandom(),
            .mockRandom(),
            .mockRandom()
        )

        let mirror = Mirror(reflecting: tuple)
        XCTAssertEqual(try mirror.descendant(path: 0), tuple.0)
        XCTAssertEqual(try mirror.descendant(path: 1), tuple.1)
        XCTAssertEqual(try mirror.descendant(path: 2), tuple.2)
        XCTAssertThrowsError(try mirror.descendant(String.self, path: 3))
    }

    func testEnumReflection() {
        enum Enum {
            case case1(Int)
            case case2(String)
            case case3(Bool)
        }

        let value1: Int = .mockRandom()
        let value2: String = .mockRandom()
        let value3: Bool = .mockRandom()

        let mirror1 = Mirror(reflecting: Enum.case1(value1))
        let mirror2 = Mirror(reflecting: Enum.case2(value2))
        let mirror3 = Mirror(reflecting: Enum.case3(value3))
        XCTAssertEqual(try mirror1.descendant(path: "case1"), value1)
        XCTAssertEqual(try mirror2.descendant(path: "case2"), value2)
        XCTAssertEqual(try mirror3.descendant(path: "case3"), value3)
        XCTAssertThrowsError(try mirror1.descendant(String.self, path: "case2"))
    }

    func testReflectableArray() throws {
        struct Value: Reflection {
            let key: String

            init(key: String) {
                self.key = key
            }

            init(_ mirror: Mirror) throws {
                self.key = try mirror.descendant(path: "key")
            }
        }

        let values = try [Value](reflecting: [Value(key: "value")])
        XCTAssertEqual(values.first?.key, "value")
    }

    func testReflectableDictionary() throws {
        struct Value: Hashable, Reflection {
            let value: String

            init(value: String) {
                self.value = value
            }

            init(_ mirror: Mirror) throws {
                self.value = try mirror.descendant(path: "value")
            }
        }

        let dict2 = try [Value: Value](reflecting: [Value(value: "key"): Value(value: "value")])
        XCTAssertEqual(dict2[Value(value: "key")]?.value, "value")
    }
}

#endif
