/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

class ReflectorTests: XCTestCase {
    func testReflectObject() throws {
        // Given
        struct Foo {
            struct Bar {
                let baz: String = "baz"
            }

            let bar: Bar = .init()
        }

        struct Echo: Reflection {
            struct Bar: Reflection {
                let baz: String

                init(from reflector: Reflector) throws {
                    baz = try reflector.descendant("baz")
                }
            }

            let bar: Bar

            init(from reflector: Reflector) throws {
                bar = try reflector.descendant("bar")
            }
        }

        // When
        let reflector = Reflector(subject: Foo(), telemetry: NOPTelemetry())
        let echo = try Echo(from: reflector)

        // Then
        XCTAssertEqual(echo.bar.baz, "baz")
    }

    func testReflectCollection() throws {
        // Given
        struct Foo {
            struct Bar {
                let baz: String = "baz"
            }

            let bar: [Any]
        }

        struct Echo: Reflection {
            struct Bar: Reflection {
                let baz: String

                init(from reflector: Reflector) throws {
                    baz = try reflector.descendant("baz")
                }
            }

            let bar: [Bar]

            init(from reflector: Reflector) throws {
                bar = try reflector.descendant("bar")
            }
        }

        // When
        let telemetry = TelemetryMock()
        // Create an array of 10 elements + an intruder
        let foo = Foo(bar: Array(repeating: Foo.Bar(), count: 10) + ["intruder"])

        let reflector = Reflector(subject: foo, telemetry: telemetry)
        let echo = try Echo(from: reflector)

        // Then
        XCTAssertEqual(echo.bar.count, 10)
        XCTAssertEqual(
            telemetry.messages.firstError()?.message,
            #"notFound(DatadogInternal.Reflector.Error.Context(subjectType: Swift.String, paths: [DatadogInternal.ReflectionMirror.Path.key("baz")]))"#
        )
    }

    func testReflectDictionary() throws {
        // Given
        struct Foo {
            struct Key: Hashable {
                let index: Int
            }

            struct Bar {
                let baz: String = "baz"
            }

            let bar: [Key: Any]
        }

        struct Echo: Reflection {
            struct Key: Hashable, Reflection {
                let index: Int
                init(from reflector: Reflector) throws {
                    index = try reflector.descendant("index")
                }
            }

            struct Bar: Reflection {
                let baz: String
                init(from reflector: Reflector) throws {
                    baz = try reflector.descendant("baz")
                }
            }

            let bar: [Key: Bar]

            init(from reflector: Reflector) throws {
                bar = try reflector.descendant("bar")
            }
        }

        // When
        let telemetry = TelemetryMock()
        // Create an dictionary of 10 elements + an intruder
        let foo = Foo(bar: (0..<10).reduce(into: [Foo.Key(index: 10): "intruder"]) { $0[Foo.Key(index: $1)] = Foo.Bar() })

        let reflector = Reflector(subject: foo, telemetry: telemetry)
        let echo = try Echo(from: reflector)

        // Then
        XCTAssertEqual(echo.bar.count, 10)
        XCTAssertEqual(
            telemetry.messages.firstError()?.message,
            #"notFound(DatadogInternal.Reflector.Error.Context(subjectType: Swift.String, paths: [DatadogInternal.ReflectionMirror.Path.key("baz")]))"#
        )
    }

    func testReflectOptional() throws {
        // Given
        struct Foo {
            struct Bar {
                let baz: String? = "baz"
                let qux: String? = nil
            }

            let bar: Bar = .init()
        }

        struct Echo: Reflection {
            struct Bar: Reflection {
                let baz: String?
                let qux: String?

                init(from reflector: Reflector) throws {
                    baz = reflector.descendantIfPresent("baz")
                    qux = reflector.descendantIfPresent("qux")
                }
            }

            let bar: Bar

            init(from reflector: Reflector) throws {
                bar = try reflector.descendant("bar")
            }
        }

        // When
        let telemetry = TelemetryMock()
        let reflector = Reflector(subject: Foo(), telemetry: telemetry)
        let echo = try Echo(from: reflector)

        // Then
        XCTAssertEqual(echo.bar.baz, "baz")
        XCTAssertNil(echo.bar.qux)
    }

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

    func testUnsupportedLayoutIncludesContext() {
        // Given
        let subject = Payload(value: "value")

        // When
        XCTAssertThrowsError(try reflector(subject).descendant(
            type: String.self, copyingIntermediates: false, "value"
        )) {
            // Then
            guard case let Reflector.Error.unsupportedLayout(context) = $0 else {
                return XCTFail("Expected unsupported layout, got \($0)")
            }
            XCTAssertTrue(context.subjectType == Payload<String>.self)
            XCTAssertEqual(context.paths.count, 1)
            guard case let .key(name)? = context.paths.first else {
                return XCTFail("Expected a named property path")
            }
            XCTAssertEqual(name, "value")
        }
    }

    func testMissingDescendantThrowsNotFound() {
        // Given
        let subject = Subject(Payload(value: "value"))

        // When
        XCTAssertThrowsError(try reflector(subject).descendant(
            type: String.self, copyingIntermediates: false, "payload", "missing"
        )) {
            // Then
            guard case Reflector.Error.notFound = $0 else {
                return XCTFail("Expected a missing field, got \($0)")
            }
        }
    }

    private func reflector(_ subject: Any) -> Reflector {
        Reflector(subject: subject, telemetry: NOPTelemetry())
    }
}

private struct Payload<Value> {
    var value: Value
}

private class Subject<Payload> {
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
