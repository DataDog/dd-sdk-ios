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
    func testDifferentSubjectCannotReenableInstalledSubjectsTelemetryDuringRefresh() throws {
        let fixture = makeSubjectTransitionFixture()
        fixture.client.setEvaluationContext(telemetryContext(.bool(true), subject: "A")) { _ in }
        fixture.complete(0, .success(()))

        fixture.client.setEvaluationContext(telemetryContext(.bool(false), subject: "B")) { _ in }
        XCTAssertTrue(fixture.client.getBooleanValue(key: "flag", defaultValue: false))
        fixture.aggregator.sendEvaluations()
        XCTAssertTrue(fixture.scope.eventsWritten.isEmpty)
        XCTAssertTrue(fixture.rum.sendFlagEvaluationCalls.isEmpty)
        XCTAssertEqual(fixture.exposures.logExposureCalls.count, 1)

        fixture.complete(1, .success(()))
        XCTAssertTrue(fixture.client.getBooleanValue(key: "flag", defaultValue: false))
        fixture.aggregator.sendEvaluations()
        XCTAssertEqual(fixture.scope.eventsWritten(ofType: FlagEvaluationEvent.self).count, 1)
        XCTAssertEqual(fixture.rum.sendFlagEvaluationCalls.count, 1)
        XCTAssertEqual(fixture.exposures.logExposureCalls.count, 2)
    }

    func testSameSubjectReenableSurvivesAnotherSubjectsPendingRefresh() {
        let fixture = makeSubjectTransitionFixture()
        fixture.client.setEvaluationContext(telemetryContext(.bool(true), subject: "A")) { _ in }
        fixture.complete(0, .success(()))

        fixture.client.setEvaluationContext(telemetryContext(.bool(false), subject: "A")) { _ in }
        fixture.client.setEvaluationContext(telemetryContext(.bool(false), subject: "B")) { _ in }
        XCTAssertTrue(fixture.client.getBooleanValue(key: "flag", defaultValue: false))
        fixture.aggregator.sendEvaluations()
        XCTAssertEqual(fixture.scope.eventsWritten(ofType: FlagEvaluationEvent.self).count, 1)
        XCTAssertEqual(fixture.rum.sendFlagEvaluationCalls.count, 1)
        XCTAssertEqual(fixture.exposures.logExposureCalls.first?.context.targetingKey, "A")
    }

    func testLateAssignmentResponseCannotRestoreAnOlderSubjectsOptIn() {
        let fixture = makeSubjectTransitionFixture()
        fixture.client.setEvaluationContext(telemetryContext(.bool(false), subject: "A")) { _ in }
        fixture.client.setEvaluationContext(telemetryContext(.bool(true), subject: "A")) { _ in }
        fixture.client.setEvaluationContext(telemetryContext(.bool(false), subject: "B")) { _ in }

        fixture.complete(0, .success(()))
        XCTAssertTrue(fixture.client.getBooleanValue(key: "flag", defaultValue: false))
        fixture.aggregator.sendEvaluations()
        XCTAssertTrue(fixture.scope.eventsWritten.isEmpty)
        XCTAssertTrue(fixture.rum.sendFlagEvaluationCalls.isEmpty)
        XCTAssertEqual(fixture.exposures.logExposureCalls.count, 1)
    }

    func testNewSubjectOptOutSuppressesPreviouslyAllowedAssignmentsImmediately() {
        let fixture = makeSubjectTransitionFixture()
        fixture.client.setEvaluationContext(telemetryContext(.bool(false), subject: "A")) { _ in }
        fixture.complete(0, .success(()))

        fixture.client.setEvaluationContext(telemetryContext(.bool(true), subject: "B")) { _ in }
        XCTAssertTrue(fixture.client.getBooleanValue(key: "flag", defaultValue: false))
        fixture.aggregator.sendEvaluations()
        XCTAssertTrue(fixture.scope.eventsWritten.isEmpty)
        XCTAssertTrue(fixture.rum.sendFlagEvaluationCalls.isEmpty)
        XCTAssertEqual(fixture.exposures.logExposureCalls.count, 1)
    }

    private func makeSubjectTransitionFixture() -> (
        client: FlagsClient,
        aggregator: EvaluationAggregator,
        scope: FeatureScopeMock,
        rum: RUMFlagEvaluationReporterMock,
        exposures: ExposureLoggerMock,
        complete: (Int, Result<Void, FlagsError>) -> Void
    ) {
        let scope = FeatureScopeMock()
        var pending: [(Result<[String: FlagAssignment], FlagsError>) -> Void] = []
        let fetcher = FlagAssignmentsFetcherMock { _, completion in pending.append(completion) }
        let repository = FlagsRepository(
            clientName: "subject-transitions",
            flagAssignmentsFetcher: fetcher,
            dateProvider: DateProviderMock(),
            featureScope: scope,
            initializationTimeout: nil
        )
        scope.dataStore.flush()
        let aggregator = EvaluationAggregator(dateProvider: DateProviderMock(), featureScope: scope, flushInterval: 100)
        let rum = RUMFlagEvaluationReporterMock()
        let exposures = ExposureLoggerMock()
        let client = FlagsClient(
            repository: repository,
            exposureLogger: exposures,
            evaluationLogger: EvaluationLogger(aggregator: aggregator),
            rumFlagEvaluationReporter: rum,
            configuration: .init(enableEvaluationTelemetryOptOutParameter: true)
        )
        let flags = telemetryFlagsData(context: telemetryContext(nil)).flags
        return (client, aggregator, scope, rum, exposures, { index, result in
            pending[index](result.map { flags })
        })
    }

    func testEvaluationTelemetryConfigurationDefaultsToDisabled() {
        XCTAssertFalse(FlagsClient.Configuration().enableEvaluationTelemetryOptOutParameter)
    }

    func testEvaluationTelemetryOptOutRequiresActivationAndTypedTrue() {
        let values: [AnyValue?] = [nil, .bool(false), .bool(true), .null, .string("true"), .int(1), .double(1), .array([.bool(true)]), .dictionary(["value": .bool(true)])]
        for enabled in [false, true] {
            for value in values {
                let fixture = makeTelemetryFixture(enabled: enabled)
                let context = telemetryContext(value)
                fixture.client.setEvaluationContext(context) { _ in }
                let details = fixture.client.getDetails(key: "flag", defaultValue: false)
                XCTAssertTrue(details.value)
                XCTAssertEqual(details.variant, "variant")
                XCTAssertEqual(details.allocationKey, "allocation")
                XCTAssertEqual(details.reason, "TARGETING_MATCH")
                XCTAssertNil(details.error)
                let expectedCount = enabled && value == .bool(true) ? 0 : 1
                XCTAssertEqual(fixture.evaluations.logEvaluationCalls.count, expectedCount, "enabled=\(enabled), value=\(String(describing: value))")
                XCTAssertEqual(fixture.rum.sendFlagEvaluationCalls.count, expectedCount)
                XCTAssertEqual(fixture.exposures.logExposureCalls.count, 1)
                XCTAssertEqual(fixture.repository.context?.attributes["dd_evaluation_telemetry_opt_out"], value)
                XCTAssertEqual(fixture.exposures.logExposureCalls.first?.context.attributes["dd_evaluation_telemetry_opt_out"], value)
            }
        }
    }

    func testOptOutSuppressesAllEvaluationErrorsAndDefaults() {
        let fixture = makeTelemetryFixture(enabled: true)
        fixture.client.setEvaluationContext(telemetryContext(.bool(true))) { _ in }
        XCTAssertEqual(fixture.client.getDetails(key: "missing", defaultValue: false).error, .flagNotFound)
        XCTAssertEqual(fixture.client.getDetails(key: "flag", defaultValue: "fallback").error, .typeMismatch)
        fixture.repository.flagsData = nil
        XCTAssertEqual(fixture.client.getDetails(key: "flag", defaultValue: false).error, .providerNotReady)
        XCTAssertTrue(fixture.evaluations.logEvaluationCalls.isEmpty)
        XCTAssertTrue(fixture.rum.sendFlagEvaluationCalls.isEmpty)
        XCTAssertTrue(fixture.exposures.logExposureCalls.isEmpty)
    }

    func testTelemetryAttributeUpdatesRefreshWithTheFullContext() {
        let fixture = makeTelemetryFixture(enabled: true)
        var requested: [FlagsEvaluationContext] = []
        fixture.repository.setEvaluationContextStub = { [weak repository = fixture.repository] context, completion in
            requested.append(context)
            repository?.flagsData?.context = context
            completion(.success(()))
        }
        fixture.client.setEvaluationContext(telemetryContext(.bool(false))) { _ in }
        var completed = 0
        fixture.client.setEvaluationContext(telemetryContext(.bool(true))) { _ in completed += 1 }
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(requested.count, 2)
        XCTAssertEqual(fixture.repository.context, telemetryContext(.bool(true)))
        _ = fixture.client.getDetails(key: "flag", defaultValue: false)
        XCTAssertTrue(fixture.evaluations.logEvaluationCalls.isEmpty)
        fixture.client.setEvaluationContext(telemetryContext(.bool(false))) { _ in completed += 1 }
        _ = fixture.client.getDetails(key: "flag", defaultValue: false)
        XCTAssertEqual(completed, 2)
        XCTAssertEqual(requested.count, 3)
        XCTAssertEqual(fixture.evaluations.logEvaluationCalls.count, 1)
        XCTAssertEqual(fixture.rum.sendFlagEvaluationCalls.count, 1)
        XCTAssertEqual(fixture.repository.context, telemetryContext(.bool(false)))

        // Repeating the same full context preserves the existing explicit refresh behavior.
        fixture.client.setEvaluationContext(telemetryContext(.bool(false))) { _ in }
        XCTAssertEqual(requested.count, 4)
        fixture.client.setEvaluationContext(telemetryContext(.bool(false), subject: "other-user")) { _ in }
        XCTAssertEqual(requested.count, 5)
        fixture.client.setEvaluationContext(.init(targetingKey: "other-user", attributes: ["plan": .string("new")])) { _ in }
        XCTAssertEqual(requested.count, 6)
    }

    func testDisabledControlPreservesAllContextUpdates() {
        let fixture = makeTelemetryFixture(enabled: false)
        var requested: [FlagsEvaluationContext] = []
        fixture.repository.setEvaluationContextStub = { [weak repository = fixture.repository] context, completion in
            requested.append(context)
            repository?.flagsData?.context = context
            completion(.success(()))
        }
        fixture.client.setEvaluationContext(telemetryContext(.bool(false))) { _ in }
        fixture.client.setEvaluationContext(telemetryContext(.bool(true))) { _ in }
        _ = fixture.client.getDetails(key: "flag", defaultValue: false)
        XCTAssertEqual(requested.map { $0.attributes["dd_evaluation_telemetry_opt_out"] }, [.bool(false), .bool(true)])
        XCTAssertEqual(fixture.evaluations.logEvaluationCalls.count, 1)
        XCTAssertEqual(fixture.rum.sendFlagEvaluationCalls.count, 1)
    }

    func testPendingOrFailedAssignmentCannotRestorePreviousTelemetryPolicy() throws {
        let fixture = makeTelemetryFixture(enabled: true)
        var pending: [(FlagsEvaluationContext, (Result<Void, FlagsError>) -> Void)] = []
        fixture.repository.setEvaluationContextStub = { context, completion in pending.append((context, completion)) }
        fixture.repository.flagsData = nil
        fixture.client.setEvaluationContext(telemetryContext(.bool(false))) { _ in }
        var completed = false
        fixture.client.setEvaluationContext(telemetryContext(.bool(true))) { _ in completed = true }
        XCTAssertFalse(completed)
        XCTAssertEqual(pending.count, 2)
        XCTAssertEqual(fixture.client.getDetails(key: "flag", defaultValue: false).error, .providerNotReady)
        XCTAssertTrue(fixture.evaluations.logEvaluationCalls.isEmpty)

        fixture.repository.flagsData = telemetryFlagsData(context: pending[0].0)
        pending[0].1(.success(()))
        XCTAssertTrue(fixture.client.getDetails(key: "flag", defaultValue: false).value)
        XCTAssertTrue(fixture.evaluations.logEvaluationCalls.isEmpty)

        pending[1].1(.failure(.invalidResponse))
        XCTAssertTrue(completed)
        XCTAssertTrue(fixture.client.getDetails(key: "flag", defaultValue: false).value)
        XCTAssertTrue(fixture.evaluations.logEvaluationCalls.isEmpty)

        fixture.client.setEvaluationContext(telemetryContext(.bool(true), subject: "other-user")) { _ in }
        XCTAssertEqual(pending.count, 3)
        fixture.repository.flagsData = nil
        pending[2].1(.failure(.invalidResponse))
        XCTAssertEqual(fixture.client.getDetails(key: "flag", defaultValue: false).error, .providerNotReady)
        XCTAssertTrue(fixture.evaluations.logEvaluationCalls.isEmpty)
        fixture.client.setEvaluationContext(telemetryContext(.bool(false), subject: "other-user")) { _ in }
        XCTAssertEqual(pending.count, 4)
        _ = fixture.client.getDetails(key: "flag", defaultValue: false)
        XCTAssertEqual(fixture.evaluations.logEvaluationCalls.count, 1)
    }

    func testTelemetryPolicyIsIndependentAcrossClientsAndCachedAssignments() {
        let optedOut = makeTelemetryFixture(enabled: true)
        let normal = makeTelemetryFixture(enabled: true)
        optedOut.repository.flagsData?.flags["flag"]?.reason = "CACHED"
        optedOut.client.setEvaluationContext(telemetryContext(.bool(true))) { _ in }
        normal.client.setEvaluationContext(telemetryContext(.bool(false))) { _ in }
        XCTAssertEqual(optedOut.client.getDetails(key: "flag", defaultValue: false).reason, "CACHED")
        XCTAssertTrue(normal.client.getDetails(key: "flag", defaultValue: false).value)
        XCTAssertTrue(optedOut.evaluations.logEvaluationCalls.isEmpty)
        XCTAssertEqual(normal.evaluations.logEvaluationCalls.count, 1)
        XCTAssertEqual(optedOut.exposures.logExposureCalls.count, 1)
    }

    func testSPIUsesTypedContextWithoutSuppressingExposures() throws {
        for enabled in [false, true] {
            let fixture = makeTelemetryFixture(enabled: enabled)
            let assignment = try XCTUnwrap(fixture.repository.flagAssignment(for: "flag"))
            fixture.client.sendFlagEvaluation(key: "flag", assignment: assignment, context: telemetryContext(.bool(true)))
            fixture.client.sendFlagEvaluation(key: "flag", assignment: assignment, context: telemetryContext(.string("true")))
            XCTAssertEqual(fixture.exposures.logExposureCalls.count, 2)
            XCTAssertEqual(fixture.exposures.logExposureCalls.map { $0.context.attributes["dd_evaluation_telemetry_opt_out"] }, [.bool(true), .string("true")])
            XCTAssertEqual(fixture.evaluations.logEvaluationCalls.count, enabled ? 1 : 2)
            XCTAssertEqual(fixture.rum.sendFlagEvaluationCalls.count, enabled ? 1 : 2)
        }
    }

    func testCachedContextControlsTelemetryUntilTheFirstContextUpdate() {
        for enabled in [false, true] {
            let fixture = makeTelemetryFixture(enabled: enabled)
            fixture.repository.flagsData = telemetryFlagsData(context: telemetryContext(.bool(true)))
            XCTAssertTrue(fixture.client.getDetails(key: "flag", defaultValue: false).value)
            XCTAssertEqual(fixture.evaluations.logEvaluationCalls.count, enabled ? 0 : 1)
            XCTAssertEqual(fixture.exposures.logExposureCalls.count, 1)
            fixture.repository.setEvaluationContextStub = { _, _ in }
            fixture.client.setEvaluationContext(telemetryContext(.bool(false))) { _ in }
            XCTAssertTrue(fixture.client.getDetails(key: "flag", defaultValue: false).value)
            XCTAssertEqual(fixture.evaluations.logEvaluationCalls.count, enabled ? 1 : 2)
        }
    }

    private func telemetryContext(_ value: AnyValue?, subject: String = "user") -> FlagsEvaluationContext {
        var attributes: [String: AnyValue] = ["plan": .string("standard")]
        attributes["dd_evaluation_telemetry_opt_out"] = value
        return .init(targetingKey: subject, attributes: attributes)
    }

    private func telemetryFlagsData(context: FlagsEvaluationContext) -> FlagsData {
        .init(
            flags: ["flag": .init(allocationKey: "allocation", variationKey: "variant", variation: .boolean(true), reason: "TARGETING_MATCH", doLog: true)],
            context: context,
            date: .mockAny()
        )
    }

    private func makeTelemetryFixture(enabled: Bool) -> (
        client: FlagsClient,
        repository: FlagsRepositoryMock,
        exposures: ExposureLoggerMock,
        evaluations: EvaluationLoggerMock,
        rum: RUMFlagEvaluationReporterMock
    ) {
        let repository = FlagsRepositoryMock(flagsData: telemetryFlagsData(context: telemetryContext(nil)))
        repository.setEvaluationContextStub = { [weak repository] context, completion in
            repository?.flagsData?.context = context
            completion(.success(()))
        }
        let exposures = ExposureLoggerMock()
        let evaluations = EvaluationLoggerMock()
        let rum = RUMFlagEvaluationReporterMock()
        return (
            FlagsClient(
                repository: repository,
                exposureLogger: exposures,
                evaluationLogger: evaluations,
                rumFlagEvaluationReporter: rum,
                configuration: .init(enableEvaluationTelemetryOptOutParameter: enabled)
            ),
            repository, exposures, evaluations, rum
        )
    }

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
