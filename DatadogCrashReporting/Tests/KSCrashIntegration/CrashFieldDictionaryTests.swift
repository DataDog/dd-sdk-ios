/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import KSCrashRecording
@testable import DatadogCrashReporting

class CrashFieldDictionaryTests: XCTestCase {
    // MARK: - init(from:) Tests

    func testInitFromDictionary_ConvertsRecursively() {
        // Given
        let input: [String: Any] = [
            "name": "MyApp",
            "crash": [
                "error": ["type": "signal"]
            ],
            "backtrace": [
                ["index": 0, "instruction_addr": "0x1000"],
                ["index": 1, "instruction_addr": "0x2000"]
            ]
        ]

        // When
        let dict = CrashFieldDictionary(from: input)

        // Then
        XCTAssertEqual(dict[.name] as? String, "MyApp")

        let crashDict = dict[.crash] as? CrashFieldDictionary
        let errorDict = crashDict?[.error] as? CrashFieldDictionary
        XCTAssertEqual(errorDict?[.type] as? String, "signal")

        let backtrace = dict[.backtrace] as? [CrashFieldDictionary]
        XCTAssertEqual(backtrace?.count, 2)
        XCTAssertEqual(backtrace?[0][.instructionAddr] as? String, "0x1000")
    }

    // MARK: - valueIfPresent Tests

    func testValueIfPresent_ReturnsValueOrNilForMissingKeys() throws {
        // Given
        let input: [String: Any] = [
            "crash": ["error": ["type": "signal"]]
        ]
        let dict = CrashFieldDictionary(from: input)

        // When/Then - existing nested value
        let value: String? = try dict.valueIfPresent(forKey: .crash, .error, .type)
        XCTAssertEqual(value, "signal")

        // When/Then - missing value
        let missing: String? = try dict.valueIfPresent(forKey: .crash, .error, .reason)
        XCTAssertNil(missing)
    }

    func testValueIfPresent_ThrowsOnTypeMismatch() {
        // Given
        let input: [String: Any] = [
            "crash": ["error": ["type": 123]]
        ]
        let dict = CrashFieldDictionary(from: input)

        // When/Then
        XCTAssertThrowsError(try dict.valueIfPresent(String.self, forKey: .crash, .error, .type)) { error in
            let exception = error as? CrashReportException
            XCTAssertNotNil(exception)
            XCTAssertTrue(exception?.description.contains("invalid type") ?? false)
            XCTAssertTrue(exception?.description.contains("crash.error.type") ?? false)
        }
    }

    // MARK: - value(forKey:) Tests

    func testValue_ReturnsValueOrThrowsForMissingKeys() throws {
        // Given
        let input: [String: Any] = [
            "crash": ["error": ["type": "signal"]]
        ]
        let dict = CrashFieldDictionary(from: input)

        // When/Then - existing nested value
        let value: String = try dict.value(forKey: .crash, .error, .type)
        XCTAssertEqual(value, "signal")

        // When/Then - missing value throws
        XCTAssertThrowsError(try dict.value(String.self, forKey: .crash, .error, .reason)) { error in
            let exception = error as? CrashReportException
            XCTAssertNotNil(exception)
            XCTAssertTrue(exception?.description.contains("missing or invalid") ?? false)
            XCTAssertTrue(exception?.description.contains("crash.error.reason") ?? false)
        }
    }

    // MARK: - setValue(forKey:) Tests

    func testSetValue_CreatesNestedStructureAndPreservesExistingData() {
        // Given
        var dict = CrashFieldDictionary()

        // When - create nested structure
        dict.setValue(forKey: .crash, .error, .type, value: "signal")
        dict.setValue(forKey: .crash, .error, .address, value: "0x0")

        // Then - both values exist
        let crashDict = dict[.crash] as? CrashFieldDictionary
        let errorDict = crashDict?[.error] as? CrashFieldDictionary
        XCTAssertEqual(errorDict?[.type] as? String, "signal")
        XCTAssertEqual(errorDict?[.address] as? String, "0x0")

        // When - overwrite existing value
        dict.setValue(forKey: .crash, .error, .type, value: "mach")

        // Then - new value replaces old
        let updatedErrorDict = (dict[.crash] as? CrashFieldDictionary)?[.error] as? CrashFieldDictionary
        XCTAssertEqual(updatedErrorDict?[.type] as? String, "mach")
        XCTAssertEqual(updatedErrorDict?[.address] as? String, "0x0")
    }
}
