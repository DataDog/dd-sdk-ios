/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

@_spi(Internal)
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
                "🔥 Datadog SDK usage error: Attempted to create a `FlagsClient` named 'default', but one already exists. The existing client will be used, and new configuration will be ignored.",
                "🔥 Datadog SDK usage error: Attempted to create a `FlagsClient` named 'test', but one already exists. The existing client will be used, and new configuration will be ignored."
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
            evaluationLogger: EvaluationLoggerMock(),
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
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
        let evaluationLogger = EvaluationLoggerMock()
        let rumFlagEvaluationReporter = RUMFlagEvaluationReporterMock()
        let client = FlagsClient(
            repository: FlagsRepositoryMock(
                flagsData: .init(
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
            evaluationLogger: evaluationLogger,
            rumFlagEvaluationReporter: rumFlagEvaluationReporter
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
                reason: "TARGETING_MATCH",
                allocationKey: "allocation-124"
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

        // Test exposure logging and RUM reporting (only successful evaluations)
        XCTAssertEqual(exposureLogger.logExposureCalls.count, 6)
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls.count, 6)

        // Test evaluation logging (all evaluations including errors)
        XCTAssertEqual(evaluationLogger.logEvaluationCalls.count, 8)
        for i in 0..<6 {
            XCTAssertNil(evaluationLogger.logEvaluationCalls[i].error, "Call \(i) should have no error")
        }
        XCTAssertNotNil(evaluationLogger.logEvaluationCalls[6].error, "flagNotFound should have error")
        XCTAssertNotNil(evaluationLogger.logEvaluationCalls[7].error, "typeMismatch should have error")
    }

    func testFlagEvaluationTracking() {
        // Given
        let exposureLogger = ExposureLoggerMock()
        let evaluationLogger = EvaluationLoggerMock()
        let rumFlagEvaluationReporter = RUMFlagEvaluationReporterMock()
        let client = FlagsClient(
            repository: FlagsRepositoryMock(
                flagsData: .init(
                    flags: [
                        "string-flag": .init(
                            allocationKey: "allocation-123",
                            variationKey: "variation-123",
                            variation: .string("red"),
                            reason: "TARGETING_MATCH",
                            doLog: true
                        ),
                    ],
                    context: .mockAny(),
                    date: .mockAny()
                )
            ),
            exposureLogger: exposureLogger,
            evaluationLogger: evaluationLogger,
            rumFlagEvaluationReporter: rumFlagEvaluationReporter
        )

        // When
        _ = client.getDetails(key: "string-flag", defaultValue: "default")

        // Then
        XCTAssertEqual(exposureLogger.logExposureCalls.count, 1)
        XCTAssertEqual(evaluationLogger.logEvaluationCalls.count, 1)
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls.count, 1)
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

        _ = client.getStringValue(key: "test", defaultValue: "default")

        // Then
        XCTAssertEqual(core.events(ofType: ExposureEvent.self).count, 0, "No exposure events should be written")
        XCTAssertEqual(messageReceiver.messages.filter(\.isRUMMessage).count, 1, "RUM integration should still work")
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

        _ = client.getStringValue(key: "test", defaultValue: "default")

        // Then
        XCTAssertEqual(core.events(ofType: ExposureEvent.self).count, 1, "Exposure should still be logged")
        XCTAssertEqual(messageReceiver.messages.filter(\.isRUMMessage).count, 0, "No RUM messages should be sent")
    }

    func testSnapshot() {
        // Given
        let exposureLogger = ExposureLoggerMock()
        let evaluationLogger = EvaluationLoggerMock()
        let rumFlagEvaluationReporter = RUMFlagEvaluationReporterMock()
        let client: FlagsClientProtocol = FlagsClient(
            repository: FlagsRepositoryMock(
                flagsData: .init(
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
            evaluationLogger: evaluationLogger,
            rumFlagEvaluationReporter: rumFlagEvaluationReporter
        )

        // When
        guard let snapshot = client.snapshot() else {
            XCTFail("Failed to get snapshot")
            return
        }

        // Then
        XCTAssertEqual(
            snapshot,
            FlagsSnapshot(
                assignments: [
                    "string-flag": FlagSnapshot(
                        value: .string("red"),
                        variant: "variation-123",
                        reason: "TARGETING_MATCH"
                    ),
                    "boolean-flag": FlagSnapshot(
                        value: .bool(true),
                        variant: "variation-124",
                        reason: "TARGETING_MATCH"
                    ),
                    "integer-flag": FlagSnapshot(
                        value: .int(42),
                        variant: "variation-125",
                        reason: "TARGETING_MATCH"
                    ),
                    "numeric-flag": FlagSnapshot(
                        value: .double(3.14),
                        variant: "variation-126",
                        reason: "TARGETING_MATCH"
                    ),
                    "json-flag": FlagSnapshot(
                        value: .dictionary(["key": .string("value"), "prop": .int(123)]),
                        variant: "variation-127",
                        reason: "TARGETING_MATCH"
                    ),
                ]
            )
        )
        XCTAssertEqual(exposureLogger.logExposureCalls.count, 0)
        XCTAssertEqual(evaluationLogger.logEvaluationCalls.count, 0)
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls.count, 0)
    }

    func testSnapshotWhenNoCachedAssignments() {
        // Given
        let client: FlagsClientProtocol = FlagsClient(
            repository: FlagsRepositoryMock(),
            exposureLogger: ExposureLoggerMock(),
            evaluationLogger: EvaluationLoggerMock(),
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )

        // When
        let snapshot = client.snapshot()

        // Then
        XCTAssertNil(snapshot)
    }

    // MARK: - Internal methods consumed by the React Native SDK

    func testGetFlagAssignments() {
        // Given
        let exposureLogger = ExposureLoggerMock()
        let rumFlagEvaluationReporter = RUMFlagEvaluationReporterMock()
        let client = FlagsClient(
            repository: FlagsRepositoryMock(
                flagsData: .init(
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
            evaluationLogger: EvaluationLoggerMock(),
            rumFlagEvaluationReporter: rumFlagEvaluationReporter
        )

        // When
        guard let flagAssignments = client.getFlagAssignments() else {
            XCTFail("Failed to get flag assignments")
            return
        }

        // Then
        XCTAssertEqual(flagAssignments.count, 5)

        // Test boolean flag
        XCTAssertEqual(flagAssignments["boolean-flag"]?.variation, .boolean(true))
        XCTAssertEqual(flagAssignments["boolean-flag"]?.allocationKey, "allocation-124")
        XCTAssertEqual(flagAssignments["boolean-flag"]?.variationKey, "variation-124")
        XCTAssertEqual(flagAssignments["boolean-flag"]?.reason, "TARGETING_MATCH")
        XCTAssertEqual(flagAssignments["boolean-flag"]?.doLog, true)

        // Test string flag
        XCTAssertEqual(flagAssignments["string-flag"]?.variation, .string("red"))
        XCTAssertEqual(flagAssignments["string-flag"]?.allocationKey, "allocation-123")
        XCTAssertEqual(flagAssignments["string-flag"]?.variationKey, "variation-123")
        XCTAssertEqual(flagAssignments["string-flag"]?.reason, "TARGETING_MATCH")
        XCTAssertEqual(flagAssignments["string-flag"]?.doLog, true)

        // Test integer flag
        XCTAssertEqual(flagAssignments["integer-flag"]?.variation, .integer(42))
        XCTAssertEqual(flagAssignments["integer-flag"]?.allocationKey, "allocation-125")
        XCTAssertEqual(flagAssignments["integer-flag"]?.variationKey, "variation-125")
        XCTAssertEqual(flagAssignments["integer-flag"]?.reason, "TARGETING_MATCH")
        XCTAssertEqual(flagAssignments["integer-flag"]?.doLog, true)

        // Test double flag
        XCTAssertEqual(flagAssignments["numeric-flag"]?.variation, .double(3.14))
        XCTAssertEqual(flagAssignments["numeric-flag"]?.allocationKey, "allocation-126")
        XCTAssertEqual(flagAssignments["numeric-flag"]?.variationKey, "variation-126")
        XCTAssertEqual(flagAssignments["numeric-flag"]?.reason, "TARGETING_MATCH")
        XCTAssertEqual(flagAssignments["numeric-flag"]?.doLog, true)

        // Test object flag
        XCTAssertEqual(
            flagAssignments["json-flag"]?.variation,
            .object(.dictionary(["key": .string("value"), "prop": .int(123)]))
        )
        XCTAssertEqual(flagAssignments["json-flag"]?.allocationKey, "allocation-127")
        XCTAssertEqual(flagAssignments["json-flag"]?.variationKey, "variation-127")
        XCTAssertEqual(flagAssignments["json-flag"]?.reason, "TARGETING_MATCH")
        XCTAssertEqual(flagAssignments["json-flag"]?.doLog, true)

        // Test that missing flag is not present
        XCTAssertNil(flagAssignments["missing-flag"])

        // Test full assignment equality for one flag
        XCTAssertEqual(
            flagAssignments["boolean-flag"],
            FlagAssignment(
                allocationKey: "allocation-124",
                variationKey: "variation-124",
                variation: .boolean(true),
                reason: "TARGETING_MATCH",
                doLog: true
            )
        )
        XCTAssertNil(flagAssignments["missing-flag"])
    }

    func testGetDetails_errorPathsHaveEmptyAllocationKey() {
        // Given — a client with no context (providerNotReady) and one string flag (for typeMismatch)
        let providerNotReadyClient = FlagsClient(
            repository: FlagsRepositoryMock(),
            exposureLogger: ExposureLoggerMock(),
            evaluationLogger: EvaluationLoggerMock(),
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )

        let clientWithFlags = FlagsClient(
            repository: FlagsRepositoryMock(
                flagsData: .init(
                    flags: [
                        "string-flag": .init(
                            allocationKey: "allocation-123",
                            variationKey: "variation-123",
                            variation: .string("red"),
                            reason: "CACHED",
                            doLog: false
                        )
                    ],
                    context: .mockAny(),
                    date: .mockAny()
                )
            ),
            exposureLogger: ExposureLoggerMock(),
            evaluationLogger: EvaluationLoggerMock(),
            rumFlagEvaluationReporter: RUMFlagEvaluationReporterMock()
        )

        // When
        let providerNotReadyDetails = providerNotReadyClient.getDetails(key: "any-flag", defaultValue: false)
        let flagNotFoundDetails = clientWithFlags.getDetails(key: "missing-flag", defaultValue: false)
        let typeMismatchDetails = clientWithFlags.getDetails(key: "string-flag", defaultValue: false)

        // Then — all error paths return nil allocationKey
        XCTAssertEqual(providerNotReadyDetails.error, .providerNotReady)
        XCTAssertNil(providerNotReadyDetails.allocationKey)
        XCTAssertNil(providerNotReadyDetails.reason)

        XCTAssertEqual(flagNotFoundDetails.error, .flagNotFound)
        XCTAssertNil(flagNotFoundDetails.allocationKey)
        XCTAssertNil(flagNotFoundDetails.reason)

        XCTAssertEqual(typeMismatchDetails.error, .typeMismatch)
        XCTAssertNil(typeMismatchDetails.allocationKey)
        XCTAssertNil(typeMismatchDetails.reason)
    }

    func testIndependentTrackingOperations() throws {
        for trackExposure in [false, true] {
            for trackEvaluation in [false, true] {
                let exposureLogger = ExposureLoggerMock()
                let evaluationLogger = EvaluationLoggerMock()
                let rumReporter = RUMFlagEvaluationReporterMock()
                let client: FlagsClientInternal = FlagsClient(
                    repository: FlagsRepositoryMock { _, _ in XCTFail("Tracking must not fetch configuration") },
                    exposureLogger: exposureLogger,
                    evaluationLogger: evaluationLogger,
                    rumFlagEvaluationReporter: rumReporter
                )
                let context = FlagsEvaluationContext(targetingKey: "captured-user", attributes: ["tier": .string("premium")])
                let assignment = FlagAssignment(
                    allocationKey: "allocation",
                    variationKey: "variant",
                    variation: .boolean(true),
                    reason: "TARGETING_MATCH",
                    doLog: true,
                    serialID: 123
                )

                if trackExposure {
                    client.sendFlagExposure(key: "flag", assignment: assignment, context: context)
                }
                if trackEvaluation {
                    client.sendFlagEvaluationEvent(key: "flag", assignment: assignment, context: context, errorCode: nil)
                }

                XCTAssertEqual(exposureLogger.logExposureCalls.count, trackExposure ? 1 : 0)
                XCTAssertEqual(evaluationLogger.logEvaluationCalls.count, trackEvaluation ? 1 : 0)
                XCTAssertTrue(rumReporter.sendFlagEvaluationCalls.isEmpty)
                if trackExposure {
                    let call = try XCTUnwrap(exposureLogger.logExposureCalls.first)
                    XCTAssertEqual(call.flagKey, "flag")
                    XCTAssertEqual(call.assignment, assignment)
                    XCTAssertEqual(call.context, context)
                }
                if trackEvaluation {
                    let call = try XCTUnwrap(evaluationLogger.logEvaluationCalls.first)
                    XCTAssertEqual(call.flagKey, "flag")
                    XCTAssertEqual(call.assignment, assignment)
                    XCTAssertEqual(call.context, context)
                    XCTAssertNil(call.error)
                }
            }
        }
    }

    func testIndependentEvaluationTrackingHandlesDefaultsAndErrors() throws {
        let exposureLogger = ExposureLoggerMock()
        let evaluationLogger = EvaluationLoggerMock()
        let rumReporter = RUMFlagEvaluationReporterMock()
        let client: FlagsClientInternal = FlagsClient(
            repository: FlagsRepositoryMock(),
            exposureLogger: exposureLogger,
            evaluationLogger: evaluationLogger,
            rumFlagEvaluationReporter: rumReporter
        )
        let context = FlagsEvaluationContext(targetingKey: "captured-user")
        let errors: [String?] = [
            nil, "PROVIDER_NOT_READY", "PROVIDER_FATAL", "FLAG_NOT_FOUND", "PARSE_ERROR", "TYPE_MISMATCH",
            "TARGETING_KEY_MISSING", "INVALID_CONTEXT", "GENERAL", "customer-sensitive-error", ""
        ]

        for error in errors {
            client.sendFlagEvaluationEvent(key: "flag", assignment: nil, context: context, errorCode: error)

            let call = try XCTUnwrap(evaluationLogger.logEvaluationCalls.last)
            XCTAssertEqual(call.flagKey, "flag")
            XCTAssertEqual(call.context, context)
            XCTAssertEqual(call.assignment.reason, "DEFAULT")
            XCTAssertEqual(call.assignment.variationKey, "")
            XCTAssertEqual(call.assignment.allocationKey, "")
            XCTAssertFalse(call.assignment.doLog)
            XCTAssertEqual(call.error, error == "customer-sensitive-error" || error == "" ? "GENERAL" : error)
        }

        XCTAssertEqual(evaluationLogger.logEvaluationCalls.count, errors.count)
        XCTAssertTrue(exposureLogger.logExposureCalls.isEmpty)
        XCTAssertTrue(rumReporter.sendFlagEvaluationCalls.isEmpty)
    }

    func testIndependentEvaluationTrackingUsesNativeAggregation() throws {
        let featureScope = FeatureScopeMock()
        let aggregator = EvaluationAggregator(
            dateProvider: DateProviderMock(now: .mockAny()),
            featureScope: featureScope,
            flushInterval: 60
        )
        let exposureLogger = ExposureLoggerMock()
        let rumReporter = RUMFlagEvaluationReporterMock()
        let client: FlagsClientInternal = FlagsClient(
            repository: FlagsRepositoryMock(),
            exposureLogger: exposureLogger,
            evaluationLogger: EvaluationLogger(aggregator: aggregator),
            rumFlagEvaluationReporter: rumReporter
        )
        let context = FlagsEvaluationContext(targetingKey: "captured-user", attributes: ["tier": .string("premium")])
        let assignment = FlagAssignment(
            allocationKey: "allocation", variationKey: "variant", variation: .boolean(true), reason: "MATCH", doLog: false
        )

        client.sendFlagEvaluationEvent(key: "success", assignment: assignment, context: context, errorCode: nil)
        client.sendFlagEvaluationEvent(key: "success", assignment: assignment, context: context, errorCode: nil)
        client.sendFlagEvaluationEvent(key: "default", assignment: nil, context: context, errorCode: nil)
        client.sendFlagEvaluationEvent(key: "error", assignment: assignment, context: context, errorCode: "TYPE_MISMATCH")
        aggregator.sendEvaluations()

        let events = featureScope.eventsWritten(ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(events.count, 3)
        let success = try XCTUnwrap(events.first { $0.flag.key == "success" })
        XCTAssertEqual(success.evaluationCount, 2)
        XCTAssertEqual(success.variant?.key, "variant")
        XCTAssertEqual(success.allocation?.key, "allocation")
        XCTAssertNil(success.runtimeDefaultUsed)
        XCTAssertNil(success.error)
        for key in ["default", "error"] {
            let event = try XCTUnwrap(events.first { $0.flag.key == key })
            XCTAssertEqual(event.evaluationCount, 1)
            XCTAssertTrue(event.runtimeDefaultUsed == true)
            XCTAssertNil(event.variant)
            XCTAssertNil(event.allocation)
            XCTAssertEqual(event.error?.message, key == "error" ? "TYPE_MISMATCH" : nil)
        }
        for event in events {
            XCTAssertEqual(event.targetingKey, "captured-user")
            XCTAssertEqual(event.context?.evaluation?["tier"], .string("premium"))
        }
        XCTAssertTrue(exposureLogger.logExposureCalls.isEmpty)
        XCTAssertTrue(rumReporter.sendFlagEvaluationCalls.isEmpty)
    }

    func testIndependentExposureTrackingPreservesDeduplicationAndDoLog() throws {
        let core = SingleFeatureCoreMock<FlagsFeature>()
        Flags.enable(in: core)
        let client = try XCTUnwrap(FlagsClient.create(in: core) as? FlagsClientInternal)
        let context = FlagsEvaluationContext(targetingKey: "captured-user")
        var assignment = FlagAssignment(
            allocationKey: "allocation",
            variationKey: "variant",
            variation: .boolean(true),
            reason: "TARGETING_MATCH",
            doLog: true,
            serialID: 123
        )

        client.sendFlagExposure(key: "flag", assignment: assignment, context: context)
        client.sendFlagExposure(key: "flag", assignment: assignment, context: context)
        assignment.serialID = 124
        client.sendFlagExposure(key: "flag", assignment: assignment, context: context)
        assignment.doLog = false
        client.sendFlagExposure(key: "other-flag", assignment: assignment, context: context)
        core.get(feature: FlagsFeature.self)?.flush()

        let events = core.events(ofType: ExposureEvent.self)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events.map(\.serialID), [123, 124])
        XCTAssertTrue(core.events(ofType: FlagEvaluationEvent.self).isEmpty)
    }

    func testIndependentTrackingRespectsDisabledFeatures() throws {
        let messageReceiver = FeatureMessageReceiverMock()
        let core = SingleFeatureCoreMock<FlagsFeature>(messageReceiver: messageReceiver)
        Flags.enable(with: .init(trackExposures: false, trackEvaluations: false), in: core)
        let client = try XCTUnwrap(FlagsClient.create(in: core) as? FlagsClientInternal)

        client.sendFlagExposure(key: "flag", assignment: .mockAnyBoolean(doLog: true), context: .mockAny())
        client.sendFlagEvaluationEvent(key: "flag", assignment: .mockAnyBoolean(), context: .mockAny(), errorCode: nil)
        client.sendFlagEvaluationEvent(key: "missing", assignment: nil, context: .mockAny(), errorCode: "FLAG_NOT_FOUND")
        core.get(feature: FlagsFeature.self)?.flush()

        XCTAssertTrue(core.events(ofType: ExposureEvent.self).isEmpty)
        XCTAssertTrue(core.events(ofType: FlagEvaluationEvent.self).isEmpty)
        XCTAssertFalse(messageReceiver.messages.contains(where: \.isRUMMessage))
    }

    func testSendFlagEvaluation() {
        // Given
        let exposureLogger = ExposureLoggerMock()
        let evaluationLogger = EvaluationLoggerMock()
        let rumFlagEvaluationReporter = RUMFlagEvaluationReporterMock()
        let client = FlagsClient(
            repository: FlagsRepositoryMock(),
            exposureLogger: exposureLogger,
            evaluationLogger: evaluationLogger,
            rumFlagEvaluationReporter: rumFlagEvaluationReporter
        )

        let context = FlagsEvaluationContext(targetingKey: "user-123")
        let booleanAssignment = FlagAssignment(
            allocationKey: "alloc-1",
            variationKey: "var-1",
            variation: .boolean(true),
            reason: "TARGETING_MATCH",
            doLog: true
        )
        let stringAssignment = FlagAssignment(
            allocationKey: "alloc-2",
            variationKey: "var-2",
            variation: .string("test"),
            reason: "TARGETING_MATCH",
            doLog: true
        )
        let integerAssignment = FlagAssignment(
            allocationKey: "alloc-3",
            variationKey: "var-3",
            variation: .integer(42),
            reason: "TARGETING_MATCH",
            doLog: true
        )
        let doubleAssignment = FlagAssignment(
            allocationKey: "alloc-4",
            variationKey: "var-4",
            variation: .double(3.14),
            reason: "TARGETING_MATCH",
            doLog: true
        )
        let objectAssignment = FlagAssignment(
            allocationKey: "alloc-5",
            variationKey: "var-5",
            variation: .object(.dictionary(["key": .string("value")])),
            reason: "TARGETING_MATCH",
            doLog: true
        )

        // When
        client.sendFlagEvaluation(key: "bool-flag", assignment: booleanAssignment, context: context)
        client.sendFlagEvaluation(key: "string-flag", assignment: stringAssignment, context: context)
        client.sendFlagEvaluation(key: "int-flag", assignment: integerAssignment, context: context)
        client.sendFlagEvaluation(key: "double-flag", assignment: doubleAssignment, context: context)
        client.sendFlagEvaluation(key: "object-flag", assignment: objectAssignment, context: context)

        // Then
        XCTAssertEqual(exposureLogger.logExposureCalls.count, 5)
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls.count, 5)

        // Test boolean tracking
        XCTAssertEqual(exposureLogger.logExposureCalls[0].flagKey, "bool-flag")
        XCTAssertEqual(exposureLogger.logExposureCalls[0].assignment, booleanAssignment)
        XCTAssertEqual(exposureLogger.logExposureCalls[0].context.targetingKey, "user-123")
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls[0].0, "bool-flag")
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls[0].1 as? String, "var-1")

        // Test string tracking
        XCTAssertEqual(exposureLogger.logExposureCalls[1].flagKey, "string-flag")
        XCTAssertEqual(exposureLogger.logExposureCalls[1].assignment, stringAssignment)
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls[1].0, "string-flag")
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls[1].1 as? String, "var-2")

        // Test integer tracking
        XCTAssertEqual(exposureLogger.logExposureCalls[2].flagKey, "int-flag")
        XCTAssertEqual(exposureLogger.logExposureCalls[2].assignment, integerAssignment)
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls[2].0, "int-flag")
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls[2].1 as? String, "var-3")

        // Test double tracking
        XCTAssertEqual(exposureLogger.logExposureCalls[3].flagKey, "double-flag")
        XCTAssertEqual(exposureLogger.logExposureCalls[3].assignment, doubleAssignment)
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls[3].0, "double-flag")
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls[3].1 as? String, "var-4")

        // Test object tracking
        XCTAssertEqual(exposureLogger.logExposureCalls[4].flagKey, "object-flag")
        XCTAssertEqual(exposureLogger.logExposureCalls[4].assignment, objectAssignment)
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls[4].0, "object-flag")
        XCTAssertEqual(rumFlagEvaluationReporter.sendFlagEvaluationCalls[4].1 as? String, "var-5")

        // Test evaluation logging
        XCTAssertEqual(evaluationLogger.logEvaluationCalls.count, 5)
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].flagKey, "bool-flag")
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].assignment, booleanAssignment)
        XCTAssertEqual(evaluationLogger.logEvaluationCalls[0].context.targetingKey, "user-123")
        XCTAssertNil(evaluationLogger.logEvaluationCalls[0].error)
    }
}

extension FeatureMessage {
    fileprivate var isRUMMessage: Bool {
        switch self {
        case .payload(let message) where message is RUMFlagEvaluationMessage:
            return true
        default:
            return false
        }
    }
}
