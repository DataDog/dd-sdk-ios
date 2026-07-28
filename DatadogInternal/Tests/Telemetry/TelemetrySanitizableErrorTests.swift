/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

/// Direct unit tests for `sanitizeForTelemetry(_:)` - the central fallback used by `Telemetry.error(_:)`
/// to sanitize any `Error` before it is forwarded to Datadog's internal telemetry.
///
/// These tests construct `EncodingError`/`DecodingError` cases directly rather than forging them through
/// a real `JSONEncoder`/`JSONDecoder` failure - `TelemetryTests.swift` covers that end-to-end path.
class TelemetrySanitizableErrorTests: XCTestCase {
    // MARK: - `TelemetrySanitizableError` conformance

    func testSanitizingConformingError_returnsItsOwnSanitizedOutputAsIs() {
        struct SanitizableError: Error, TelemetrySanitizableError {
            let secret = "should never reach telemetry"

            func sanitize() -> TelemetrySanitizedError {
                TelemetrySanitizedError(kind: "custom-kind", message: "custom-message", stack: "custom-stack")
            }
        }

        let sanitized = sanitizeForTelemetry(SanitizableError())

        XCTAssertEqual(sanitized.kind, "custom-kind")
        XCTAssertEqual(sanitized.message, "custom-message")
        XCTAssertEqual(sanitized.stack, "custom-stack")
    }

    // MARK: - `EncodingError`

    func testSanitizingEncodingErrorInvalidValue_neverReportsTheRawOffendingValue() {
        // Given
        // The raw offending value is `EncodingError.invalidValue(_:_:)`'s first associated value - the one
        // that leaks in full when an `EncodingError` is described via `"\(error)"`.
        let sensitiveValue = "sensitive-value-\(String.mockRandom(length: 16))"
        let error = EncodingError.invalidValue(
            sensitiveValue,
            EncodingError.Context(codingPath: [], debugDescription: "cannot encode value")
        )

        // When
        let sanitized = sanitizeForTelemetry(error)

        // Then
        XCTAssertEqual(sanitized.kind, "EncodingError.invalidValue")
        XCTAssertEqual(sanitized.message, "cannot encode value")
        XCTAssertNil(sanitized.stack, "stack must be nil when codingPath is empty")
        XCTAssertFalse(sanitized.message.contains(sensitiveValue))
    }

    func testSanitizingEncodingErrorInvalidValue_withNonEmptyCodingPath_reportsItAsStack() {
        // Given
        let error = EncodingError.invalidValue(
            "value",
            EncodingError.Context(codingPath: [DynamicCodingKey("foo"), DynamicCodingKey("bar")], debugDescription: "cannot encode value")
        )

        // When
        let sanitized = sanitizeForTelemetry(error)

        // Then
        XCTAssertEqual(sanitized.stack, "foo.bar")
    }

    // MARK: - `DecodingError`

    func testSanitizingDecodingErrorTypeMismatch() {
        let error = DecodingError.typeMismatch(
            Int.self,
            DecodingError.Context(codingPath: [], debugDescription: "expected Int, found a string")
        )

        let sanitized = sanitizeForTelemetry(error)

        XCTAssertEqual(sanitized.kind, "DecodingError.typeMismatch")
        XCTAssertEqual(sanitized.message, "expected Int, found a string")
        XCTAssertNil(sanitized.stack)
    }

    func testSanitizingDecodingErrorValueNotFound() {
        let error = DecodingError.valueNotFound(
            String.self,
            DecodingError.Context(codingPath: [DynamicCodingKey("foo")], debugDescription: "expected value, found null")
        )

        let sanitized = sanitizeForTelemetry(error)

        XCTAssertEqual(sanitized.kind, "DecodingError.valueNotFound")
        XCTAssertEqual(sanitized.message, "expected value, found null")
        XCTAssertEqual(sanitized.stack, "foo")
    }

    func testSanitizingDecodingErrorKeyNotFound() {
        let error = DecodingError.keyNotFound(
            DynamicCodingKey("foo"),
            DecodingError.Context(codingPath: [], debugDescription: "key not found")
        )

        let sanitized = sanitizeForTelemetry(error)

        XCTAssertEqual(sanitized.kind, "DecodingError.keyNotFound")
        XCTAssertEqual(sanitized.message, "key not found")
        XCTAssertNil(sanitized.stack)
    }

    func testSanitizingDecodingErrorDataCorrupted() {
        let error = DecodingError.dataCorrupted(
            DecodingError.Context(codingPath: [DynamicCodingKey("foo"), DynamicCodingKey("bar")], debugDescription: "data corrupted")
        )

        let sanitized = sanitizeForTelemetry(error)

        XCTAssertEqual(sanitized.kind, "DecodingError.dataCorrupted")
        XCTAssertEqual(sanitized.message, "data corrupted")
        XCTAssertEqual(sanitized.stack, "foo.bar")
    }

    // MARK: - `NSError`

    func testSanitizingNSError_reportsOnlyDomainAndCode() {
        // Given
        // `userInfo` can carry customer-supplied data (e.g. `NSLocalizedDescriptionKey`), so it must
        // never be reported - only `domain`/`code`.
        let error = NSError(
            domain: "custom-domain",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "sensitive description"]
        )

        // When
        let sanitized = sanitizeForTelemetry(error)

        // Then
        XCTAssertEqual(sanitized.kind, "NSError")
        XCTAssertEqual(sanitized.message, "custom-domain (10)")
        XCTAssertNil(sanitized.stack)
    }

    // MARK: - Unrecognized error types

    func testSanitizingUnrecognizedError_reportsOnlyItsTypeName() {
        // Given
        struct CustomError: Error {
            let secret = "should never reach telemetry"
        }

        // When
        let sanitized = sanitizeForTelemetry(CustomError())

        // Then
        XCTAssertEqual(sanitized.kind, "CustomError")
        XCTAssertEqual(sanitized.message, "Unrecognized error type: CustomError")
        XCTAssertEqual(sanitized.stack, "Implement TelemetrySanitizableError on CustomError to report richer, safe context.")
    }
}
