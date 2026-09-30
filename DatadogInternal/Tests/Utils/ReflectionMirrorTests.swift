/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class ReflectionMirrorTests: XCTestCase {
    func testClassDisplay() {
        class Mock {}
        let mirror = ReflectionMirror(reflecting: Mock())
        XCTAssertEqual(mirror.displayStyle, .class)
    }

    func testStructDisplay() {
        struct Mock {}
        let mirror = ReflectionMirror(reflecting: Mock())
        XCTAssertEqual(mirror.displayStyle, .struct)
    }

    func testTupleDisplay() {
        let mirror = ReflectionMirror(reflecting: (1, 2))
        XCTAssertEqual(mirror.displayStyle, .tuple)
    }

    func testEnumDisplay() {
        enum Mock {
            case test
        }
        let mirror = ReflectionMirror(reflecting: Mock.test)
        XCTAssertEqual(mirror.displayStyle, .enum(case: "test"))
    }

    func testNilDisplay() {
        struct Mock {}
        let mirror = ReflectionMirror(reflecting: Optional<Mock>.none as Any)
        XCTAssertEqual(mirror.displayStyle, .nil)
    }

    func testNonNilDisplay() {
        struct Mock {}
        let mirror = ReflectionMirror(reflecting: Optional.some(Mock()) as Any)
        XCTAssertEqual(mirror.displayStyle, .struct)
    }

    func testAccessingDescendant() {
        struct Foo {
            let bar: Bar = .init()
        }

        struct Bar {
            let baz: String = "baz"
        }

        let mirror = ReflectionMirror(reflecting: (Foo(), Bar()))
        XCTAssertEqual(mirror.descendant(0, "bar", "baz") as? String, "baz")
        XCTAssertEqual(mirror.descendant(1, "baz") as? String, "baz")
    }

    func testGenericLeafValues() throws {
        // Given
        struct LargeValue: Equatable {
            let a: Int
            let b: Int
            let c: Int
            let d: Int
            let text: String
        }
        let large = LargeValue(a: 1, b: 2, c: 3, d: 4, text: "large")
        func read<Value>(_ value: Value) throws -> Any? {
            try ReflectionMirror(reflecting: Subject(Payload(value: value))).descendant(
                copyingIntermediates: false, ["payload", "value"]
            )
        }

        // When
        let largeValue = try read(large)
        let none = try XCTUnwrap(read(Optional<String>.none))
        let void = try XCTUnwrap(read(()))

        // Then
        XCTAssertEqual(largeValue as? LargeValue, large)
        XCTAssertTrue(type(of: none) == String?.self)
        XCTAssertNil(none as? String)
        XCTAssertTrue(void is Void)
    }

    func testExistentialLeafIsOpenedByTheRuntime() throws {
        // Given
        let value: Any = [42: "value"]
        let subject = Subject(Payload(value: value))
        let void: Any = ()
        let voidSubject = Subject(Payload(value: void))

        // When
        let dictionary = try ReflectionMirror(reflecting: subject).descendant(
            copyingIntermediates: false, ["payload", "value"]
        )
        let reflected = try XCTUnwrap(ReflectionMirror(reflecting: voidSubject).descendant(
            copyingIntermediates: false, ["payload", "value"]
        ))

        // Then
        XCTAssertEqual(dictionary as? [Int: String], [42: "value"])
        XCTAssertTrue(reflected is Void)
    }

    func testNestedAndInheritedStoredFields() throws {
        // Given
        class Derived: Subject<Payload<Payload<String>>> {
            let otherValue = "other"
        }
        let subject = Derived(Payload(value: Payload(value: "leaf")))

        // When
        let value = try ReflectionMirror(reflecting: subject).descendant(
            copyingIntermediates: false, ["payload", "value", "value"]
        )

        // Then
        XCTAssertEqual(value as? String, "leaf")
    }

    func testDirectClassFieldAndOptionalRoot() throws {
        // Given
        class Owner { let value = 42 }
        let subject: Owner? = Owner()

        // When
        let value = try ReflectionMirror(reflecting: subject as Any).descendant(
            copyingIntermediates: false, ["value"]
        )

        // Then
        XCTAssertEqual(value as? Int, 42)
    }

    func testLeafOutlivesOwner() throws {
        // Given
        weak var owner: Subject<Payload<[Int: NSObject]>>?
        weak var value: NSObject?

        // When
        let descendant: Any? = try {
            let subject = Subject(Payload(value: [42: NSObject()]))
            owner = subject
            value = subject.payload.value[42]
            return try ReflectionMirror(reflecting: subject).descendant(
                copyingIntermediates: false, ["payload", "value"]
            )
        }()

        // Then
        XCTAssertNil(owner)
        let dictionary = try XCTUnwrap(descendant as? [Int: NSObject])
        let retainedValue = try XCTUnwrap(dictionary[42])
        XCTAssertTrue(retainedValue === value)
    }

    func testUnsupportedRootsAndIntermediateLayouts() {
        // Given
        class ReferencePayload { let value = "value" }
        let subjects: [Any] = [
            Payload(value: "value"),
            NSObject(),
            Subject(ReferencePayload()),
            Subject(Optional.some(Payload(value: "value"))),
            Subject((Payload(value: "value"), 0))
        ]

        for subject in subjects {
            // When
            XCTAssertThrowsError(try ReflectionMirror(reflecting: subject).descendant(
                copyingIntermediates: false, ["payload", "value"]
            )) {
                // Then
                guard case ReflectionMirror.Error.unsupportedLayout = $0 else {
                    return XCTFail("Expected unsupported layout, got \($0)")
                }
            }
        }
    }

    func testIndexPathsAreRejected() {
        // Given
        let mirror = ReflectionMirror(reflecting: Subject(Payload(value: "value")))

        // When
        XCTAssertThrowsError(try mirror.descendant(copyingIntermediates: false, ["payload", 1])) {
            // Then
            guard case ReflectionMirror.Error.unsupportedLayout = $0 else {
                return XCTFail("Expected unsupported layout, got \($0)")
            }
        }
    }

    func testMissingAndEmptyPaths() throws {
        // Given
        let mirror = ReflectionMirror(reflecting: Subject(Payload(value: "value")))
        let paths: [[ReflectionMirror.Path]] = [["missing"], ["payload", "missing"], []]

        for path in paths {
            // When
            let value = try mirror.descendant(copyingIntermediates: false, path)

            // Then
            XCTAssertNil(value)
        }
    }

    func testWeakAndDanglingUnownedFieldsAreRejected() {
        // Given
        struct UnownedPayload { unowned let value: NSObject }
        struct WeakPayload { weak var value: NSObject? }
        let unownedSubject: Subject<UnownedPayload> = {
            let object = NSObject()
            return Subject(UnownedPayload(value: object))
        }()
        let subjects: [Any] = [unownedSubject, Subject(WeakPayload(value: nil))]

        for subject in subjects {
            // When
            XCTAssertThrowsError(try ReflectionMirror(reflecting: subject).descendant(
                copyingIntermediates: false, ["payload", "value"]
            )) {
                // Then
                guard case ReflectionMirror.Error.unsupportedLayout = $0 else {
                    return XCTFail("Expected unsupported ownership, got \($0)")
                }
            }
        }
    }
}

private struct Payload<Value> {
    let padding: UInt8 = 1
    var value: Value
    var unrelated = [42: NSObject()]
}

private class Subject<Payload> {
    let padding: Int = 2
    var payload: Payload

    init(_ payload: Payload) {
        self.payload = payload
    }
}
