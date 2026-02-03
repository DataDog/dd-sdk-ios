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
}
