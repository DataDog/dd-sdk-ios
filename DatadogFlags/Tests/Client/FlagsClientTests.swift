/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogFlags

final class FlagsClientTests: XCTestCase {
    func testCreate() {
        // Given
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        // When
        let defaultClient = FlagsClient.create(in: core)
        let nopDefaultClient = FlagsClient.create(in: core)
        let namedClient = FlagsClient.create(name: "test", in: core)
        let nopNamedClient = FlagsClient.create(name: "test", in: core)

        // Then
        XCTAssertTrue(defaultClient is FlagsClient)
        XCTAssertTrue(nopDefaultClient is NOPFlagsClient)
        XCTAssertTrue(namedClient is FlagsClient)
        XCTAssertTrue(nopNamedClient is NOPFlagsClient)
    }

    func testCreateWhenFlagsNotEnabled() {
        // Given
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let core = FeatureRegistrationCoreMock()

        // When
        let client = FlagsClient.create(in: core)

        // Then
        XCTAssertTrue(client is NOPFlagsClient)
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Flags feature must be enabled before calling `FlagsClient.create(name:with:in:)`."
        )
    }

    func testInstance() {
        // Given
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        // When
        let createdClient = FlagsClient.create(in: core)
        let client = FlagsClient.instance(in: core)
        let createdNamedClient = FlagsClient.create(name: "test", in: core)
        let namedClient = FlagsClient.instance(named: "test", in: core)

        // Then
        XCTAssertIdentical(client, createdClient)
        XCTAssertIdentical(namedClient, createdNamedClient)
    }

    func testNotFoundInstance() {
        // Given
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        // When
        let notFoundClient = FlagsClient.instance(named: "foo", in: core)

        // Then
        XCTAssertTrue(notFoundClient is NOPFlagsClient)
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Flags client 'foo' not found. Make sure that you call `FlagsClient.create(name:with:in:)` first."
        )
    }

    func testInstanceWhenFlagsNotEnabled() {
        // Given
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let core = FeatureRegistrationCoreMock()

        // When
        let client = FlagsClient.instance(in: core)

        // Then
        XCTAssertTrue(client is NOPFlagsClient)
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Flags feature must be enabled before calling `FlagsClient.instance(named:in:)`."
        )
    }

    func testSetEvaluationContext() {
        // Given
        var capturedContext: FlagsEvaluationContext?
        let client = FlagsClient(
            repository: FlagsRepositoryMock { context, completion in
                capturedContext = context
                completion(.success(()))
            },
            exposureLogger: ExposureLoggerMock(),
            rumExposureLogger: RUMExposureLoggerMock()
        )

        let context = FlagsEvaluationContext(targetingKey: "test")
        let completed = expectation(description: "completed")

        // When
        var capturedResult: Result<Void, FlagsError>?
        client.setEvaluationContext(context) { result in
            capturedResult = result
            completed.fulfill()
        }

        // Then
        waitForExpectations(timeout: 0)
        XCTAssertNotNil(capturedResult)
        XCTAssertNoThrow(try capturedResult?.get())
        XCTAssertEqual(capturedContext?.targetingKey, "test")
    }

    func testFlagEvaluation() {
        // Given
        let exposureLogger = ExposureLoggerMock()
        let rumExposureLogger = RUMExposureLoggerMock()
        let client = FlagsClient(
            repository: FlagsRepositoryMock(
                state: .init(
                    flags: [
                        "string-flag": .init(
                            allocationKey: "allocation-123",
                            variationKey: "variation-123",
                            variation: .string("red"),
                            reason: "TARGETING_MATCH",
                            doLog: true
                        ),
                        "boolean-flag": .init(
                            allocationKey: "allocation-124",
                            variationKey: "variation-124",
                            variation: .boolean(true),
                            reason: "TARGETING_MATCH",
                            doLog: true
                        ),
                        "integer-flag": .init(
                            allocationKey: "allocation-125",
                            variationKey: "variation-125",
                            variation: .integer(42),
                            reason: "TARGETING_MATCH",
                            doLog: true
                        ),
                        "numeric-flag": .init(
                            allocationKey: "allocation-126",
                            variationKey: "variation-126",
                            variation: .double(3.14),
                            reason: "TARGETING_MATCH",
                            doLog: true
                        ),
                        "json-flag": .init(
                            allocationKey: "allocation-127",
                            variationKey: "variation-127",
                            variation: .object(
                                .dictionary(["key": .string("value"), "prop": .int(123)])
                            ),
                            reason: "TARGETING_MATCH",
                            doLog: true
                        ),
                    ],
                    context: .mockAny(),
                    date: .mockAny()
                )
            ),
            exposureLogger: exposureLogger,
            rumExposureLogger: rumExposureLogger
        )

        // When
        let boolValue = client.getBooleanValue(key: "boolean-flag", defaultValue: false)
        let stringValue = client.getStringValue(key: "string-flag", defaultValue: "default")
        let integerValue = client.getIntegerValue(key: "integer-flag", defaultValue: 0)
        let doubleValue = client.getDoubleValue(key: "numeric-flag", defaultValue: 0.0)
        let objectValue = client.getObjectValue(key: "json-flag", defaultValue: .null)

        let boolDetails = client.getBooleanDetails(key: "boolean-flag", defaultValue: false)
        let flagNotFoundDetails = client.getBooleanDetails(key: "missing-flag", defaultValue: false)
        let typeMismatchDetails = client.getBooleanDetails(key: "string-flag", defaultValue: false)

        // Then
        XCTAssertTrue(boolValue)
        XCTAssertEqual(stringValue, "red")
        XCTAssertEqual(integerValue, 42)
        XCTAssertEqual(doubleValue, 3.14, accuracy: 0.001)
        XCTAssertEqual(
            objectValue,
            .dictionary(
                [
                    "key": .string("value"),
                    "prop": .int(123)
                ]
            )
        )
        XCTAssertEqual(
            boolDetails,
            FlagDetails(
                key: "boolean-flag",
                value: true,
                variant: "variation-124",
                reason: "TARGETING_MATCH"
            )
        )
        XCTAssertEqual(
            flagNotFoundDetails,
            .init(
                key: "missing-flag",
                value: false,
                error: .flagNotFound
            )
        )
        XCTAssertEqual(
            typeMismatchDetails,
            .init(
                key: "string-flag",
                value: false,
                error: .typeMismatch
            )
        )
        XCTAssertEqual(exposureLogger.logExposureCalls.count, 6)
        XCTAssertEqual(rumExposureLogger.logExposureCalls.count, 6)
    }

    func testClientWithNOPLoggers() {
        // Given
        let client = FlagsClient(
            repository: FlagsRepositoryMock(
                state: .init(
                    flags: [
                        "test-flag": .init(
                            allocationKey: "allocation-123",
                            variationKey: "variation-123",
                            variation: .boolean(true),
                            reason: "TARGETING_MATCH",
                            doLog: true
                        )
                    ],
                    context: .mockAny(),
                    date: .mockAny()
                )
            ),
            exposureLogger: NOPExposureLogger(),
            rumExposureLogger: NOPRUMExposureLogger()
        )

        // When
        let result = client.getBooleanValue(key: "test-flag", defaultValue: false)

        // Then - Should work normally without any errors from NOP loggers
        XCTAssertTrue(result)
    }

    func testConfigurationControlsLoggerInjection() {
        // Test that the correct logger types are injected based on configuration flags
        let testCases: [(enableExposureLogging: Bool, enableRUMIntegration: Bool, description: String)] = [
            (true, true, "both enabled"),
            (false, false, "both disabled"),
            (true, false, "exposure only"),
            (false, true, "RUM only")
        ]

        for testCase in testCases {
            // Given
            let core = FeatureRegistrationCoreMock()
            let config = Flags.Configuration(
                enableExposureLogging: testCase.enableExposureLogging,
                enableRUMIntegration: testCase.enableRUMIntegration
            )

            // When
            Flags.enable(with: config, in: core)
            let client = FlagsClient.create(in: core) as! FlagsClient

            // Then - Verify correct logger types are injected
            let expectedNOPExposure = !testCase.enableExposureLogging
            let expectedNOPRUM = !testCase.enableRUMIntegration

            XCTAssertEqual(
                client.isUsingNOPExposureLogger,
                expectedNOPExposure,
                "ExposureLogger type incorrect for \(testCase.description)"
            )
            XCTAssertEqual(
                client.isUsingNOPRUMLogger,
                expectedNOPRUM,
                "RUMExposureLogger type incorrect for \(testCase.description)"
            )

            // Also verify end-to-end functionality works without crashes
            let result = client.getBooleanValue(key: "nonexistent-flag", defaultValue: false)
            XCTAssertFalse(result, "Should return default value for \(testCase.description)")
        }
    }
}
