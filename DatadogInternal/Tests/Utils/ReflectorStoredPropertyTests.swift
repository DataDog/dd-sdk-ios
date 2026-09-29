/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogInternal

class ReflectorStoredPropertyTests: XCTestCase {
    func testDictionaryUsesItsActualTypeBeforeCasting() throws {
        // Given
        struct Key: Hashable { let id: Int }
        let key = Key(id: 42)
        let object = NSObject()
        let subject = Subject(Payload(value: [key: object]))

        // When
        let dictionary: [AnyHashable: Any] = try reflector(subject).descendant(
            copyingIntermediates: false, "payload", "value"
        )

        // Then
        XCTAssertEqual(dictionary.count, 1)
        XCTAssertTrue(dictionary[key] as? NSObject === object)
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
        func read<Value>(_ value: Value) throws -> Value {
            try reflector(Subject(Payload(value: value))).descendant(
                type: Value.self, copyingIntermediates: false, "payload", "value"
            )
        }

        // When
        let largeValue = try read(large)
        let none = try read(Optional<String>.none)
        let void: Void = try read(())

        // Then
        XCTAssertEqual(largeValue, large)
        XCTAssertNil(none)
        XCTAssertTrue(void == ())
    }

    func testExistentialLeafIsOpenedByTheRuntime() throws {
        // Given
        let value: Any = [42: "value"]
        let subject = Subject(Payload(value: value))
        let void: Any = ()
        let voidSubject = Subject(Payload(value: void))

        // When
        let dictionary: [Int: String] = try reflector(subject).descendant(
            copyingIntermediates: false, "payload", "value"
        )
        let reflected: Any = try reflector(voidSubject).descendant(
            copyingIntermediates: false, "payload", "value"
        )

        // Then
        XCTAssertEqual(dictionary, [42: "value"])
        XCTAssertTrue(reflected is Void)
    }

    func testNestedAndInheritedStoredFields() throws {
        // Given
        class Derived: Subject<Payload<Payload<String>>> {
            let otherValue = "other"
        }
        let subject = Derived(Payload(value: Payload(value: "leaf")))

        // When
        let value: String = try reflector(subject).descendant(
            copyingIntermediates: false, ["payload", "value", "value"]
        )

        // Then
        XCTAssertEqual(value, "leaf")
    }

    func testDirectClassFieldAndOptionalRoot() throws {
        // Given
        class Owner { let value = 42 }
        let subject: Owner? = Owner()

        // When
        let value: Int = try reflector(subject as Any).descendant(
            copyingIntermediates: false, "value"
        )

        // Then
        XCTAssertEqual(value, 42)
    }

    func testLeafOutlivesOwner() throws {
        // Given
        weak var owner: Subject<Payload<[Int: NSObject]>>?
        weak var value: NSObject?

        // When
        let dictionary: [AnyHashable: Any] = try {
            let subject = Subject(Payload(value: [42: NSObject()]))
            owner = subject
            value = subject.payload.value[42]
            return try reflector(subject).descendant(copyingIntermediates: false, "payload", "value")
        }()

        // Then
        XCTAssertNil(owner)
        let retainedValue = try XCTUnwrap(dictionary[42] as? NSObject)
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
            XCTAssertThrowsError(try reflector(subject).descendant(
                type: String.self, copyingIntermediates: false, "payload", "value"
            )) {
                // Then
                guard case Reflector.Error.unsupportedLayout = $0 else {
                    return XCTFail("Expected unsupported layout, got \($0)")
                }
            }
        }
    }

    func testIndexPathsAreRejected() {
        // Given
        let subject = Subject(Payload(value: "value"))

        // When
        XCTAssertThrowsError(try reflector(subject).descendant(
            type: String.self, copyingIntermediates: false, "payload", 1
        )) {
            // Then
            guard case Reflector.Error.unsupportedLayout = $0 else {
                return XCTFail("Expected unsupported layout, got \($0)")
            }
        }
    }

    func testMissingAndEmptyPaths() {
        // Given
        let reader = reflector(Subject(Payload(value: "value")))
        let paths: [[ReflectionMirror.Path]] = [["missing"], ["payload", "missing"], []]

        for path in paths {
            // When
            XCTAssertThrowsError(try reader.descendant(
                type: String.self, copyingIntermediates: false, path
            )) {
                // Then
                guard case Reflector.Error.notFound = $0 else {
                    return XCTFail("Expected a missing field, got \($0)")
                }
            }
        }
    }

    func testTypeMismatchUsesActualLeafType() {
        // Given
        let subject = Subject(Payload(value: 42))

        // When
        XCTAssertThrowsError(try reflector(subject).descendant(
            type: String.self, copyingIntermediates: false, "payload", "value"
        )) {
            // Then
            guard case let Reflector.Error.typeMismatch(_, expect: expected, got: actual) = $0 else {
                return XCTFail("Expected a type mismatch, got \($0)")
            }
            XCTAssertTrue(expected == String.self)
            XCTAssertTrue(actual == Int.self)
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
            XCTAssertThrowsError(try reflector(subject).descendant(
                type: Any.self, copyingIntermediates: false, "payload", "value"
            )) {
                // Then
                guard case Reflector.Error.unsupportedLayout = $0 else {
                    return XCTFail("Expected unsupported ownership, got \($0)")
                }
            }
        }
    }

    func testDefaultAndExplicitCopyingPreserveExistingTraversal() throws {
        // Given
        let subject = Payload(value: Optional.some(Payload(value: "value")))
        let reader = reflector(subject)

        // When
        let defaultCopying: String = try reader.descendant("value", "value")
        let arrayPath: String = try reader.descendant(["value", "value"])
        let explicitCopying: String = try reader.descendant(
            copyingIntermediates: true, "value", "value"
        )

        // Then
        XCTAssertEqual(defaultCopying, "value")
        XCTAssertEqual(arrayPath, "value")
        XCTAssertEqual(explicitCopying, "value")
    }

    func testReflectionConversion() throws {
        // Given
        struct Value { let text: String }
        let subject = Subject(Payload(value: Value(text: "value")))

        // When
        let reflected: TextReflection = try reflector(subject).descendant(
            copyingIntermediates: false, "payload", "value"
        )

        // Then
        XCTAssertEqual(reflected.text, "value")
    }

    private func reflector(_ subject: Any) -> Reflector {
        Reflector(subject: subject, telemetry: NOPTelemetry())
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

private struct TextReflection: Reflection {
    let text: String

    init(from reflector: Reflector) throws {
        text = try reflector.descendant("text")
    }
}
