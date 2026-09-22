/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogInternal

/// Direct unit tests for `TelemetrySanitizedError.init(sanitizing:)` - the central fallback used by
/// `Telemetry.error(_:)` to sanitize any `Error` before it is forwarded to Datadog's internal telemetry.
class TelemetrySanitizableErrorTests: XCTestCase {
    // MARK: - `TelemetrySanitizableError` conformance

    func testSanitizingConformingError_returnsItsOwnSanitizedOutputAsIs() {
        struct SanitizableError: Error, TelemetrySanitizableError {
            let secret = "should never reach telemetry"

            func sanitize() -> TelemetrySanitizedError {
                TelemetrySanitizedError(kind: "custom-kind", message: "custom-message", stack: "custom-stack")
            }
        }

        let sanitized = TelemetrySanitizedError(sanitizing: SanitizableError())

        XCTAssertEqual(sanitized.kind, "custom-kind")
        XCTAssertEqual(sanitized.message, "custom-message")
        XCTAssertEqual(sanitized.stack, "custom-stack")
    }

    // MARK: - `EncodingError`

    private func forgeEncodingError<T: Encodable>(encoding value: T, file: StaticString = #filePath, line: UInt = #line) -> EncodingError {
        do {
            _ = try JSONEncoder().encode(value)
            XCTFail("Expected encoding to fail", file: file, line: line)
            fatalError("Expected encoding to fail")
        } catch let error as EncodingError {
            return error
        } catch {
            XCTFail("Expected an EncodingError, got \(error)", file: file, line: line)
            fatalError("Expected an EncodingError, got \(error)")
        }
    }

    func testSanitizingEncodingErrorInvalidValue_forTopLevelNonConformingFloat_neverReportsFoundationsDebugDescription() {
        // Given
        let error = forgeEncodingError(encoding: Double.nan)

        // When
        let sanitized = TelemetrySanitizedError(sanitizing: error)

        // Then
        XCTAssertEqual(sanitized.kind, "EncodingError.invalidValue")
        XCTAssertEqual(sanitized.message, "value could not be encoded")
        XCTAssertNil(sanitized.stack, "stack must be nil when codingPath is empty")
    }

    func testSanitizingEncodingErrorInvalidValue_forNestedNonConformingFloat_reportsCodingPathDepthOnly() {
        // Given
        struct Model: Encodable { let value: Double }
        let error = forgeEncodingError(encoding: Model(value: .infinity))

        // When
        let sanitized = TelemetrySanitizedError(sanitizing: error)

        // Then
        XCTAssertEqual(sanitized.kind, "EncodingError.invalidValue")
        XCTAssertEqual(sanitized.message, "value could not be encoded")
        XCTAssertEqual(sanitized.stack, "1 level deep", "codingPath must be reported as depth, never the literal key name")
    }

    func testSanitizingEncodingErrorInvalidValue_forDeeplyNestedNonConformingFloat_reportsCodingPathDepthOnly() {
        // Given
        struct Inner: Encodable { let value: Double }
        struct Outer: Encodable { let inner: Inner }
        let error = forgeEncodingError(encoding: Outer(inner: Inner(value: .infinity)))

        // When
        let sanitized = TelemetrySanitizedError(sanitizing: error)

        // Then
        XCTAssertEqual(sanitized.kind, "EncodingError.invalidValue")
        XCTAssertEqual(sanitized.message, "value could not be encoded")
        XCTAssertEqual(sanitized.stack, "2 levels deep", "codingPath must be reported as depth, never the literal key names")
    }

    // MARK: - `DecodingError`

    private struct Response: Decodable { let count: Int }
    private struct NestedResponse: Decodable { let inner: Response }

    private func forgeDecodingError<T: Decodable>(decoding json: String, as type: T.Type, file: StaticString = #filePath, line: UInt = #line) -> DecodingError {
        do {
            _ = try JSONDecoder().decode(type, from: Data(json.utf8))
            XCTFail("Expected decoding to fail", file: file, line: line)
            fatalError("Expected decoding to fail")
        } catch let error as DecodingError {
            return error
        } catch {
            XCTFail("Expected a DecodingError, got \(error)", file: file, line: line)
            fatalError("Expected a DecodingError, got \(error)")
        }
    }

    private func forgeDecodingError(decoding json: String, file: StaticString = #filePath, line: UInt = #line) -> DecodingError {
        forgeDecodingError(decoding: json, as: Response.self, file: file, line: line)
    }

    func testSanitizingDecodingErrorTypeMismatch() {
        // Given
        let sensitiveValue = "sensitive-value-\(String.mockRandom(length: 16))"
        let error = forgeDecodingError(decoding: "{\"count\": \"\(sensitiveValue)\"}")

        // When
        let sanitized = TelemetrySanitizedError(sanitizing: error)

        // Then
        XCTAssertEqual(sanitized.kind, "DecodingError.typeMismatch")
        XCTAssertEqual(sanitized.message, "decoded value had an unexpected type")
        XCTAssertEqual(sanitized.stack, "1 level deep", "codingPath must be reported as depth, never the literal key name")
        XCTAssertFalse(sanitized.message.contains(sensitiveValue))
        XCTAssertFalse((sanitized.stack ?? "").contains(sensitiveValue))
    }

    func testSanitizingDecodingErrorTypeMismatch_whenDeeplyNested_reportsCodingPathDepthOnly() {
        // Given
        let sensitiveValue = "sensitive-value-\(String.mockRandom(length: 16))"
        let error = forgeDecodingError(decoding: "{\"inner\": {\"count\": \"\(sensitiveValue)\"}}", as: NestedResponse.self)

        // When
        let sanitized = TelemetrySanitizedError(sanitizing: error)

        // Then
        XCTAssertEqual(sanitized.kind, "DecodingError.typeMismatch")
        XCTAssertEqual(sanitized.message, "decoded value had an unexpected type")
        XCTAssertEqual(sanitized.stack, "2 levels deep", "codingPath must be reported as depth, never the literal key names")
        XCTAssertFalse((sanitized.stack ?? "").contains(sensitiveValue))
    }

    func testSanitizingDecodingErrorValueNotFound() {
        // Given
        let error = forgeDecodingError(decoding: "{\"count\": null}")

        // When
        let sanitized = TelemetrySanitizedError(sanitizing: error)

        // Then
        XCTAssertEqual(sanitized.kind, "DecodingError.valueNotFound")
        XCTAssertEqual(sanitized.message, "expected value was missing")
        XCTAssertEqual(sanitized.stack, "1 level deep")
    }

    func testSanitizingDecodingErrorKeyNotFound() {
        // Given
        let error = forgeDecodingError(decoding: "{}")

        // When
        let sanitized = TelemetrySanitizedError(sanitizing: error)

        // Then
        XCTAssertEqual(sanitized.kind, "DecodingError.keyNotFound")
        XCTAssertEqual(sanitized.message, "expected key was missing")
        XCTAssertNil(sanitized.stack, "codingPath is empty when the missing key is at the top level")
    }

    func testSanitizingDecodingErrorDataCorrupted() {
        // Given
        let sensitiveValue = "sensitive-payload-\(String.mockRandom(length: 16))"
        let error = forgeDecodingError(decoding: "{\"count\": 1, \"extra\": \"\(sensitiveValue)\" not-valid-json-after-this")

        // When
        let sanitized = TelemetrySanitizedError(sanitizing: error)

        // Then
        XCTAssertEqual(sanitized.kind, "DecodingError.dataCorrupted")
        XCTAssertEqual(sanitized.message, "data was corrupted")
        XCTAssertNil(sanitized.stack)
        XCTAssertFalse(sanitized.message.contains(sensitiveValue))
    }

    // MARK: - `NSError`

    func testSanitizingNSError_reportsOnlyDomainAndCode() {
        // Given
        let error = NSError(
            domain: "custom-domain",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "sensitive description"]
        )

        // When
        let sanitized = TelemetrySanitizedError(sanitizing: error)

        // Then
        XCTAssertEqual(sanitized.kind, "NSError")
        XCTAssertEqual(sanitized.message, "domain: custom-domain, code: 10")
        XCTAssertNil(sanitized.stack)
    }

    // MARK: - Unrecognized error types

    func testSanitizingUnrecognizedError_reportsOnlyItsTypeName() {
        // Given
        struct CustomError: Error {
            let secret = "should never reach telemetry"
        }

        // When
        let sanitized = TelemetrySanitizedError(sanitizing: CustomError())

        // Then
        XCTAssertEqual(sanitized.kind, "CustomError")
        XCTAssertEqual(sanitized.message, "CustomError does not conform to TelemetrySanitizableError — reporting type name only")
        XCTAssertEqual(sanitized.stack, "Implement TelemetrySanitizableError on CustomError to report richer, safe context.")
    }
}
