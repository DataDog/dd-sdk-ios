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
        XCTAssertEqual(error.stack, "error.stack")
        XCTAssertEqual(telemetry.messages.count, 1)
    }

    func testSendingErrorTelemetry_whenNoKindAndNoStack() throws {
        // When
        #sourceLocation(file: "File.swift", line: 1)
        telemetry.error("error message", kind: nil, stack: nil)
        #sourceLocation()

        // Then
        let error = try XCTUnwrap(telemetry.messages.firstError())
        XCTAssertEqual(error.id, "\(moduleName())/File.swift:1:error message")
        XCTAssertEqual(error.message, "error message")
        XCTAssertEqual(error.kind, "\(moduleName())/FileError")
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
        telemetry.error(swiftError)
        telemetry.error("custom message", error: swiftError)

        // Then
        let errors = telemetry.messages.compactMap({ $0.asError })
        XCTAssertEqual(telemetry.messages.count, 2)
        XCTAssertEqual(errors[0].message, #"SwiftError(description: "error description")"#)
        XCTAssertEqual(errors[0].kind, "SwiftError")
        XCTAssertEqual(errors[0].stack, #"SwiftError(description: "error description")"#)
        XCTAssertEqual(errors[1].message, #"custom message - SwiftError(description: "error description")"#)
        XCTAssertEqual(errors[1].kind, "SwiftError")
        XCTAssertEqual(errors[1].stack, #"SwiftError(description: "error description")"#)
    }

    func testSendingErrorTelemetry_withNSError() throws {
        // Given
        let nsError = NSError(
            domain: "custom-domain",
            code: 10,
            userInfo: [NSLocalizedDescriptionKey: "error description"]
        )

        // When
        telemetry.error(nsError)
        telemetry.error("custom message", error: nsError)

        // Then
        let errors = telemetry.messages.compactMap({ $0.asError })
        XCTAssertEqual(telemetry.messages.count, 2)
        XCTAssertEqual(errors[0].message, "error description")
        XCTAssertEqual(errors[0].kind, "custom-domain - 10")
        XCTAssertEqual(errors[0].stack, #"Error Domain=custom-domain Code=10 "error description" UserInfo={NSLocalizedDescription=error description}"#)
        XCTAssertEqual(errors[1].message, "custom message - error description")
        XCTAssertEqual(errors[1].kind, "custom-domain - 10")
        XCTAssertEqual(errors[1].stack, #"Error Domain=custom-domain Code=10 "error description" UserInfo={NSLocalizedDescription=error description}"#)
    }

    // MARK: - Configuration Telemetry

    func testSendingConfigurationTelemetry() throws {
        // When
        telemetry.configuration(batchSize: 123, batchUploadFrequency: 456) // only some values

        // Then
        let configuration = try XCTUnwrap(telemetry.messages.firstConfiguration())
        XCTAssertEqual(configuration.batchSize, 123)
        XCTAssertEqual(configuration.batchUploadFrequency, 456)
    }

    // MARK: - Metric Telemetry

    func testSendingMetricTelemetry() throws {
        // When
        telemetry.metric(name: "metric name", attributes: ["attribute": "value"])

        // Then
        let metric = try XCTUnwrap(telemetry.messages.compactMap({ $0.asMetric }).first)
        XCTAssertEqual(metric.name, "metric name")
        XCTAssertEqual(metric.attributes as? [String: String], ["attribute": "value"])
    }

    func testStartingMethodCalledMetricTrace_whenSampled() throws {
        XCTAssertNotNil(telemetry.startMethodCalled(operationName: .mockAny(), callerClass: .mockAny(), samplingRate: 100))
    }

    func testStartingMethodCalledMetricTrace_whenNotSampled() throws {
        XCTAssertNil(telemetry.startMethodCalled(operationName: .mockAny(), callerClass: .mockAny(), samplingRate: 0))
    }

    func testTrackingMethodCallMetricTelemetry() throws {
        let operationName: String = .mockRandom()
        let callerClass: String = .mockRandom()
        let isSuccessful: Bool = .random()

        // When
        let metricTrace = telemetry.startMethodCalled(operationName: operationName, callerClass: callerClass, samplingRate: 100)
        Thread.sleep(forTimeInterval: 0.05)
        telemetry.stopMethodCalled(metricTrace, isSuccessful: isSuccessful)

        // Then
        let metric = try XCTUnwrap(telemetry.messages.firstMetric(named: MethodCalledMetric.name))
        XCTAssertEqual(metric.attributes[SDKMetricFields.typeKey] as? String, MethodCalledMetric.typeValue)
        XCTAssertEqual(metric.attributes[MethodCalledMetric.operationName] as? String, operationName)
        XCTAssertEqual(metric.attributes[MethodCalledMetric.callerClass] as? String, callerClass)
        XCTAssertEqual(metric.attributes[MethodCalledMetric.isSuccessful] as? Bool, isSuccessful)
        let executionTime = try XCTUnwrap(metric.attributes[MethodCalledMetric.executionTime] as? Int64)
        XCTAssertGreaterThan(executionTime, 0)
        XCTAssertLessThan(executionTime, TimeInterval(1).toInt64Nanoseconds)
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

        core.telemetry.metric(name: "metric name", attributes: [:])
        XCTAssertEqual(receiver.messages.lastTelemetry?.asMetric?.name, "metric name")

        let metricTrace = core.telemetry.startMethodCalled(operationName: .mockAny(), callerClass: .mockAny())
        core.telemetry.stopMethodCalled(metricTrace)
        XCTAssertEqual(receiver.messages.lastTelemetry?.asMetric?.name, MethodCalledMetric.name)
    }
}
