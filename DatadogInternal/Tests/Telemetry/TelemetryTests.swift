/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import Foundation
import TestUtilities
@testable import DatadogInternal

class TelemetryTests: XCTestCase {
    private let telemetry = TelemetryMock()

    // MARK: - Debug Telemetry

    func testSendingDebugTelemetry() throws {
        // When
        #sourceLocation(file: "File.swift", line: 1)
        telemetry.debug("debug message", attributes: ["foo": "bar"])
        #sourceLocation()

        // Then
        let debug = try XCTUnwrap(telemetry.messages.firstDebug())
        XCTAssertEqual(debug.id, "\(moduleName())/File.swift:1:debug message")
        XCTAssertEqual(debug.message, "debug message")
        XCTAssertEqual(debug.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(telemetry.messages.count, 1)
    }

    // MARK: - Error Telemetry

    func testSendingErrorTelemetry() throws {
        // When
        #sourceLocation(file: "File.swift", line: 1)
        telemetry.error("error message", kind: "error.kind", stack: "error.stack")
        #sourceLocation()

        // Then
        let error = try XCTUnwrap(telemetry.messages.firstError())
        XCTAssertEqual(error.id, "\(moduleName())/File.swift:1:error message")
        XCTAssertEqual(error.message, "error message")
        XCTAssertEqual(error.kind, "error.kind")
        XCTAssertEqual(error.stack, "\(moduleName())/File.swift:1\nerror.stack")
        XCTAssertEqual(telemetry.messages.count, 1)
    }

    func testSendingErrorTelemetry_whenNoKindAndNoStack() throws {
        // When
        #sourceLocation(file: "File.swift", line: 1)
        telemetry.error("error message")
        #sourceLocation()

        // Then
        let error = try XCTUnwrap(telemetry.messages.firstError())
        XCTAssertEqual(error.id, "\(moduleName())/File.swift:1:error message")
        XCTAssertEqual(error.message, "error message")
        XCTAssertEqual(error.kind, "\(moduleName())/File.swift")
        XCTAssertEqual(error.stack, "\(moduleName())/File.swift:1")
        XCTAssertEqual(telemetry.messages.count, 1)
    }

    func testSendingErrorTelemetry_withSwiftError() throws {
        // Given
        struct SwiftError: Error {
            let description = "error description"
        }
        let swiftError = SwiftError()

        // When
        #sourceLocation(file: "File.swift", line: 1)
        telemetry.error(swiftError)
        telemetry.error("custom message", error: swiftError)
        #sourceLocation()

        // Then
        // `SwiftError` doesn't conform to `TelemetrySanitizableError`, isn't `EncodingError`/`DecodingError`/`NSError`,
        // so it falls back to the type-name-only default - its raw associated values must never leak into telemetry.
        let errors = telemetry.messages.compactMap({ $0.asError })
        XCTAssertEqual(telemetry.messages.count, 2)
        XCTAssertEqual(errors[0].message, "SwiftError does not conform to TelemetrySanitizableError — reporting type name only")
        XCTAssertEqual(errors[0].kind, "SwiftError")
        XCTAssertEqual(errors[0].stack, "\(moduleName())/File.swift:1\nImplement TelemetrySanitizableError on SwiftError to report richer, safe context.")
        XCTAssertEqual(errors[1].message, "custom message - SwiftError does not conform to TelemetrySanitizableError — reporting type name only")
        XCTAssertEqual(errors[1].kind, "SwiftError")
        XCTAssertEqual(errors[1].stack, "\(moduleName())/File.swift:2\nImplement TelemetrySanitizableError on SwiftError to report richer, safe context.")
    }

    func testSendingErrorTelemetry_withSanitizableSwiftError() throws {
        // Given
        struct SanitizableSwiftError: Error, TelemetrySanitizableError {
            let secret = "should never reach telemetry"

            func sanitize() -> TelemetrySanitizedError {
                TelemetrySanitizedError(kind: "SanitizableSwiftError", message: "sanitized message", stack: "sanitized stack")
            }
        }
        let error = SanitizableSwiftError()

        // When
        #sourceLocation(file: "File.swift", line: 1)
        telemetry.error(error)
        telemetry.error("custom message", error: error)
        #sourceLocation()

        // Then
        // Conforming to `TelemetrySanitizableError` opts out of the default fallback - `sanitize()`'s
        // output is reported as-is.
        let errors = telemetry.messages.compactMap({ $0.asError })
        XCTAssertEqual(telemetry.messages.count, 2)
        XCTAssertEqual(errors[0].message, "sanitized message")
        XCTAssertEqual(errors[0].kind, "SanitizableSwiftError")
        XCTAssertEqual(errors[0].stack, "\(moduleName())/File.swift:1\nsanitized stack")
        XCTAssertEqual(errors[1].message, "custom message - sanitized message")
        XCTAssertEqual(errors[1].kind, "SanitizableSwiftError")
        XCTAssertEqual(errors[1].stack, "\(moduleName())/File.swift:2\nsanitized stack")
    }

    // RUM-17396: `AnyEncodable`'s `encode(to:)` falls back to a `default:` branch for values
    // it cannot cast to a supported shape (e.g. a dictionary with non-`String` keys), throwing
    // an `EncodingError` whose default Swift description embeds the whole raw offending value.
    // If such an error reaches `Telemetry.error`, that raw value must be dropped before it is
    // sent through internal telemetry.
    func testSendingErrorTelemetry_doesNotCaptureRawAttributeValueFromAnyEncodableEncodingError() throws {
        // Given
        // Forge `AnyEncodable`'s encoding error by encoding an unsupported value.
        func forgeAnyEncodableEncodingError(capturing attributeValue: String) -> Error {
            struct CustomKey: Hashable {
                func hash(into hasher: inout Hasher) { hasher.combine(42) }
            }
            let unsupportedEncodable = [CustomKey(): attributeValue]
            let encodable = AnyEncodable(unsupportedEncodable)
            do {
                _ = try JSONEncoder().encode(encodable)
                XCTFail("Encoding with custom key should fail")
                fatalError("Encoding with custom key should fail")
            } catch {
                return error
            }
        }

        let attributeValue = "attribute-value-\(String.mockRandom(length: 16))"
        let encodingError = forgeAnyEncodableEncodingError(capturing: attributeValue)
        XCTAssertTrue("\(encodingError)".contains(attributeValue), "the forged error captures the raw attribute value")

        // When
        telemetry.error("failed to encode attribute", error: encodingError)

        // Then
        let error = try XCTUnwrap(telemetry.messages.compactMap({ $0.asError }).first)
        XCTAssertFalse("\(error)".contains(attributeValue), "error must not capture raw attribute values: \(error)")
    }

    // `DecodingError` doesn't conform to `TelemetrySanitizableError`, so it goes through
    // `TelemetrySanitizedError.init(sanitizing:)`'s dedicated `DecodingError` branch - only `context.debugDescription`/
    // `codingPath` must be reported, never the raw decoded value.
    func testSendingErrorTelemetry_withDecodingError() throws {
        // Given
        struct Response: Decodable { let count: Int }
        let sensitiveValue = "sensitive-value-\(String.mockRandom(length: 16))"
        let json = "{\"count\": \"\(sensitiveValue)\"}".data(using: .utf8)! // `count` should be an `Int`, not a `String`

        let decodingError: DecodingError
        do {
            _ = try JSONDecoder().decode(Response.self, from: json)
            XCTFail("Decoding a type-mismatched value should fail")
            fatalError("Decoding a type-mismatched value should fail")
        } catch let error as DecodingError {
            decodingError = error
        } catch {
            XCTFail("Expected a DecodingError, got \(error)")
            fatalError("Expected a DecodingError, got \(error)")
        }

        // When
        telemetry.error("failed to decode response", error: decodingError)

        // Then
        let error = try XCTUnwrap(telemetry.messages.compactMap({ $0.asError }).first)
        XCTAssertEqual(error.kind, "DecodingError.typeMismatch")
        XCTAssertFalse("\(error)".contains(sensitiveValue), "error must not capture raw decoded values: \(error)")
    }

    func testSendingErrorTelemetry_withNSError() throws {
        // Given
        let nsError = NSError(
            domain: "custom-domain",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "error description"]
        )

        // When
        #sourceLocation(file: "File.swift", line: 1)
        telemetry.error(nsError)
        telemetry.error("custom message", error: nsError)
        #sourceLocation()

        // Then
        // `NSError`'s `userInfo` can carry customer-supplied data (e.g. `NSLocalizedDescriptionKey`), so
        // only its domain/code are reported - never `userInfo` or the default `"\(nsError)"` description.
        // `TelemetrySanitizedError.stack` is nil here, so `Telemetry.error` falls back to its own
        // `"\(file):\(line)"` default - the call site above, not the error's own stack.
        let errors = telemetry.messages.compactMap({ $0.asError })
        XCTAssertEqual(telemetry.messages.count, 2)
        XCTAssertEqual(errors[0].message, "domain: custom-domain, code: 10")
        XCTAssertEqual(errors[0].kind, "NSError")
        XCTAssertEqual(errors[0].stack, "\(moduleName())/File.swift:1")
        XCTAssertEqual(errors[1].message, "custom message - domain: custom-domain, code: 10")
        XCTAssertEqual(errors[1].kind, "NSError")
        XCTAssertEqual(errors[1].stack, "\(moduleName())/File.swift:2")
    }

    func testSendingErrorTelemetry_withSanitizableNSError() throws {
        // Given
        // A dedicated `NSError` subclass declaring its own `TelemetrySanitizableError` conformance -
        // not a retroactive `extension NSError: TelemetrySanitizableError`, which the protocol's docs warn
        // against since it would be a single, global fact about the (NSError, TelemetrySanitizableError) pair.
        final class SanitizableNSError: NSError, TelemetrySanitizableError {
            func sanitize() -> TelemetrySanitizedError {
                TelemetrySanitizedError(kind: "SanitizableNSError", message: "sanitized message", stack: "sanitized stack")
            }
        }
        let error = SanitizableNSError(domain: "custom-domain", code: 10, userInfo: [NSLocalizedDescriptionKey: "error description"])

        // When
        #sourceLocation(file: "File.swift", line: 1)
        telemetry.error(error)
        telemetry.error("custom message", error: error)
        #sourceLocation()

        // Then
        let errors = telemetry.messages.compactMap({ $0.asError })
        XCTAssertEqual(telemetry.messages.count, 2)
        XCTAssertEqual(errors[0].message, "sanitized message")
        XCTAssertEqual(errors[0].kind, "SanitizableNSError")
        XCTAssertEqual(errors[0].stack, "\(moduleName())/File.swift:1\nsanitized stack")
        XCTAssertEqual(errors[1].message, "custom message - sanitized message")
        XCTAssertEqual(errors[1].kind, "SanitizableNSError")
        XCTAssertEqual(errors[1].stack, "\(moduleName())/File.swift:2\nsanitized stack")
    }

    // MARK: - Configuration Telemetry

    func testSendingConfigurationTelemetry() throws {
        // When
        telemetry.configuration(backgroundTasksEnabled: true, batchSize: 123, batchUploadFrequency: 456) // only some values

        // Then
        let configuration = try XCTUnwrap(telemetry.messages.firstConfiguration())
        XCTAssertEqual(configuration.batchSize, 123)
        XCTAssertEqual(configuration.batchUploadFrequency, 456)
        XCTAssertEqual(configuration.backgroundTasksEnabled, true)
    }

    // MARK: - Metric Telemetry

    func testSendingMetricTelemetry() throws {
        // When
        telemetry.metric(name: "metric name", attributes: ["attribute": "value"], sampleRate: 4.21)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.compactMap({ $0.asMetric }).first)
        XCTAssertEqual(metric.name, "metric name")
        XCTAssertEqual(metric.attributes as? [String: String], ["attribute": "value"])
        XCTAssertEqual(metric.sampleRate, 4.21)
    }

    func testMetricTelemetryDefaultSampleRate() throws {
        // When
        telemetry.metric(name: "metric name", attributes: [:])

        // Then
        let metric = try XCTUnwrap(telemetry.messages.compactMap({ $0.asMetric }).first)
        XCTAssertEqual(metric.sampleRate, MetricTelemetry.defaultSampleRate)
    }

    func testHeadSampleRateInMethodCalledMetric() throws {
        XCTAssertNotNil(telemetry.startMethodCalled(operationName: .mockAny(), callerClass: .mockAny(), headSampleRate: 100))
        XCTAssertNil(telemetry.startMethodCalled(operationName: .mockAny(), callerClass: .mockAny(), headSampleRate: 0))
    }

    func testDefaultTailSampleRateInMethodCalledMetric() throws {
        let metricTrace = telemetry.startMethodCalled(operationName: .mockAny(), callerClass: .mockAny(), headSampleRate: 100)
        telemetry.stopMethodCalled(metricTrace, isSuccessful: .mockAny())

        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: MethodCalledMetric.name))
        XCTAssertEqual(metric.sampleRate, MetricTelemetry.defaultSampleRate)
    }

    func testTailSampleRateInMethodCalledMetric() throws {
        let metricTrace = telemetry.startMethodCalled(operationName: .mockAny(), callerClass: .mockAny(), headSampleRate: 100)
        telemetry.stopMethodCalled(metricTrace, isSuccessful: .mockAny(), tailSampleRate: 42.5)

        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: MethodCalledMetric.name))
        XCTAssertEqual(metric.sampleRate, 42.5)
    }

    func testTrackingMethodCallMetricTelemetry() throws {
        let operationName: String = .mockRandom()
        let callerClass: String = .mockRandom()
        let isSuccessful: Bool = .random()

        // When
        let metricTrace = telemetry.startMethodCalled(operationName: operationName, callerClass: callerClass, headSampleRate: 100)
        Thread.sleep(forTimeInterval: 0.05)
        telemetry.stopMethodCalled(metricTrace, isSuccessful: isSuccessful)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: MethodCalledMetric.name))
        XCTAssertEqual(metric.attributes[SDKMetricFields.typeKey] as? String, MethodCalledMetric.typeValue)
        XCTAssertEqual(metric.attributes[SDKMetricFields.headSampleRate] as? SampleRate, 100)
        XCTAssertEqual(metric.attributes[MethodCalledMetric.operationName] as? String, operationName)
        XCTAssertEqual(metric.attributes[MethodCalledMetric.callerClass] as? String, callerClass)
        XCTAssertEqual(metric.attributes[MethodCalledMetric.isSuccessful] as? Bool, isSuccessful)
        let executionTime = try XCTUnwrap(metric.attributes[MethodCalledMetric.executionTime] as? Int64)
        XCTAssertGreaterThan(executionTime, 0)
        XCTAssertLessThan(executionTime, TimeInterval(1).dd.toInt64Nanoseconds)
        XCTAssertEqual(metric.sampleRate, MetricTelemetry.defaultSampleRate)
    }

    // MARK: - Integration with Core

    func testWhenUsingCoreTelemetry_itSendsTelemetryToMessageReceiver() throws {
        let receiver = FeatureMessageReceiverMock()
        let core = PassthroughCoreMock(messageReceiver: receiver)

        core.telemetry.debug("debug message")
        XCTAssertEqual(receiver.messages.lastTelemetry?.asDebug?.message, "debug message")

        core.telemetry.error("error message")
        XCTAssertEqual(receiver.messages.lastTelemetry?.asError?.message, "error message")

        core.telemetry.configuration(batchSize: 123)
        XCTAssertEqual(receiver.messages.lastTelemetry?.asConfiguration?.batchSize, 123)

        core.telemetry.metric(name: "metric name", attributes: [:], sampleRate: 15)
        XCTAssertEqual(receiver.messages.lastTelemetry?.asMetric?.name, "metric name")

        let metricTrace = core.telemetry.startMethodCalled(operationName: .mockAny(), callerClass: .mockAny(), headSampleRate: 100)
        core.telemetry.stopMethodCalled(metricTrace)
        XCTAssertEqual(receiver.messages.lastTelemetry?.asMetric?.name, MethodCalledMetric.name)
    }
}
