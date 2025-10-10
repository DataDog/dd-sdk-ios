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
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        // When
        let defaultClient = FlagsClient.create(in: core)
        let otherDefaultClient = FlagsClient.create(in: core)
        let namedClient = FlagsClient.create(name: "test", in: core)
        let otherNamedClient = FlagsClient.create(name: "test", in: core)

        // Then
        XCTAssertTrue(defaultClient is FlagsClient)
        XCTAssertIdentical(defaultClient, otherDefaultClient)
        XCTAssertTrue(namedClient is FlagsClient)
        XCTAssertIdentical(namedClient, otherNamedClient)
        XCTAssertEqual(
            printFunction.printedMessages,
            [
                "🔥 Datadog SDK usage error: Attempted to create a `FlagsClient` named 'default', but one already exists. The existing client will be used, and any new configuration will be ignored.",
                "🔥 Datadog SDK usage error: Attempted to create a `FlagsClient` named 'test', but one already exists. The existing client will be used, and any new configuration will be ignored."
            ]
        )
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
        XCTAssertTrue(client is FallbackFlagsClient)
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Failed to create `FlagsClient` named 'default': Flags feature must be enabled first. Call `Flags.enable()` before creating clients. Operating in no-op mode."
        )
    }

    func testSharedInstance() {
        // Given
        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        // When
        let createdClient = FlagsClient.create(in: core)
        let client = FlagsClient.shared(in: core)
        let createdNamedClient = FlagsClient.create(name: "test", in: core)
        let namedClient = FlagsClient.shared(named: "test", in: core)

        // Then
        XCTAssertIdentical(client, createdClient)
        XCTAssertIdentical(namedClient, createdNamedClient)
    }

    func testNotFoundSharedInstance() {
        // Given
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let core = FeatureRegistrationCoreMock()
        Flags.enable(in: core)

        // When
        let notFoundClient = FlagsClient.shared(named: "foo", in: core)

        // Then
        XCTAssertTrue(notFoundClient is FallbackFlagsClient)
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Attempted to use a `FlagsClient` named 'foo', but no such client exists. Create the client with `FlagsClient.create(name:in:)` before using it. Operating in no-op mode."
        )
    }

    func testSharedInstanceWhenFlagsNotEnabled() {
        // Given
        let printFunction = PrintFunctionSpy()
        consolePrint = printFunction.print
        defer { consolePrint = { message, _ in print(message) } }

        let core = FeatureRegistrationCoreMock()

        // When
        let client = FlagsClient.shared(in: core)

        // Then
        XCTAssertTrue(client is FallbackFlagsClient)
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: Attempted to use a `FlagsClient` named 'default', but no such client exists. Create the client with `FlagsClient.create(name:in:)` before using it. Operating in no-op mode."
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

    func testExposureTrackingDisabled() throws {
        // Given
        let initialState = FlagsData(
            flags: ["test": .mockAnyString()],
            context: .mockAny(),
            date: .mockAny()
        )
        let data = try JSONEncoder().encode(initialState)
        let messageReceiver = FeatureMessageReceiverMock()
        let core = SingleFeatureCoreMock<FlagsFeature>(
            dataStore: DataStoreMock(
                storage: [
                    FlagsClient.defaultName: .value(data, dataStoreDefaultKeyVersion)
                ]
            ),
            messageReceiver: messageReceiver
        )

        // When
        Flags.enable(with: .init(trackExposures: false), in: core)
        let client = FlagsClient.create(in: core)
        let value = client.getStringValue(key: "test", defaultValue: "")

        // Then
        XCTAssertEqual(value, .mockAny())
        XCTAssertEqual(core.events(ofType: ExposureEvent.self).count, 0, "No exposure events should be written")
        XCTAssertEqual(messageReceiver.messages.filter(\.isFlagsRUMMessage).count, 2, "RUM integration should still work")
    }

    func testRUMIntegrationDisabled() throws {
        // Given
        let initialState = FlagsData(
            flags: ["test": .mockAnyString()],
            context: .mockAny(),
            date: .mockAny()
        )
        let data = try JSONEncoder().encode(initialState)
        let messageReceiver = FeatureMessageReceiverMock()
        let core = SingleFeatureCoreMock<FlagsFeature>(
            dataStore: DataStoreMock(
                storage: [
                    FlagsClient.defaultName: .value(data, dataStoreDefaultKeyVersion)
                ]
            ),
            messageReceiver: messageReceiver
        )

        // When
        Flags.enable(with: .init(rumIntegrationEnabled: false), in: core)
        let client = FlagsClient.create(in: core)
        let value = client.getStringValue(key: "test", defaultValue: "")

        // Then
        XCTAssertEqual(value, .mockAny())
        XCTAssertEqual(messageReceiver.messages.filter(\.isFlagsRUMMessage).count, 0, "No RUM messages should be sent")
        XCTAssertEqual(core.events(ofType: ExposureEvent.self).count, 1, "Exposure should still be logged")
    }
}

extension FeatureMessage {
    fileprivate var isFlagsRUMMessage: Bool {
        switch self {
        case .payload(let message) where message is RUMFlagEvaluationMessage:
            return true
        case .payload(let message) where message is RUMFlagExposureMessage:
            return true
        default:
            return false
        }
    }
}
