/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
import Network

@testable import DatadogCore
@testable import DatadogRUM

@_spi(Internal)
@testable import DatadogFlags

/// Covers integration scenarios for flag evaluation logging.
final class FlagsEvaluationIntegrationTests: XCTestCase {
    func testImmediateOptOutDeliveryAndTelemetry() throws {
        try runOptOutDeliveryAndTelemetry(mode: .immediate)
    }

    func testFutureOptOutDeliveryAndTelemetry() throws {
        try runOptOutDeliveryAndTelemetry(mode: .futureExperimentsOnly)
    }

    func testExperimentationOptOutPreservesExposuresWhenEvaluationTelemetryIsSuppressed() throws {
        try runOptOutDeliveryAndTelemetry(mode: .immediate, suppressTelemetry: true)
        try runOptOutDeliveryAndTelemetry(mode: .futureExperimentsOnly, suppressTelemetry: true)
    }

    private func runOptOutDeliveryAndTelemetry(mode: FlagsClient.ExperimentationOptOutMode, suppressTelemetry: Bool = false) throws {
        let server = OptOutAssignmentsStub()
        let core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
        defer { try? core.flushAndTearDown() }
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            featureScope: core.scope(for: FlagsFeature.self),
            fetch: server.fetch
        )
        try Flags.enableOrThrow(with: .init(evaluationFlushInterval: 60), in: core, flagAssignmentsFetcher: fetcher)
        let client = FlagsClient.create(configuration: .init(
            enableEvaluationTelemetryOptOutParameter: true,
            experimentationOptOutMode: mode
        ), in: core)

        let initial = expectation(description: "eligible response")
        client.setEvaluationContext(.init(targetingKey: "subject", attributes: ["dd_evaluation_telemetry_opt_out": .bool(suppressTelemetry)])) { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            initial.fulfill()
        }
        waitForExpectations(timeout: 5)
        XCTAssertTrue(client.getBooleanValue(key: "flag", defaultValue: false))

        let withdrawn = expectation(description: "ordinary fallback")
        client.setEvaluationContext(.init(
            targetingKey: "subject",
            attributes: [
                "dd_experimentation_opt_out_at": .string("2099-01-01T02:00:00.123456789+02:00"),
                "dd_evaluation_telemetry_opt_out": .bool(suppressTelemetry)
            ]
        )) { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            withdrawn.fulfill()
        }
        waitForExpectations(timeout: 5)
        XCTAssertFalse(client.getBooleanValue(key: "flag", defaultValue: true))
        XCTAssertEqual(client.getStringValue(key: "string", defaultValue: "default"), "ordinary")
        XCTAssertEqual(client.getIntegerValue(key: "integer", defaultValue: 0), 42)
        XCTAssertEqual(client.getDoubleValue(key: "double", defaultValue: 0), 1.5)
        XCTAssertEqual(client.getObjectValue(key: "object", defaultValue: .null), .dictionary(["ordinary": .bool(true)]))
        XCTAssertEqual(server.options, [false, true])
        if mode == .futureExperimentsOnly {
            XCTAssertTrue(client.getBooleanValue(key: "older", defaultValue: false))
        }

        let invalid = expectation(description: "invalid context")
        client.setEvaluationContext(.init(
            targetingKey: "subject", attributes: [
                "dd_experimentation_opt_out_at": .bool(true),
                "dd_evaluation_telemetry_opt_out": .bool(suppressTelemetry)
            ]
        )) { result in
            guard case .failure(.invalidContext) = result else {
                return XCTFail("Expected invalid context")
            }
            invalid.fulfill()
        }
        waitForExpectations(timeout: 1)
        XCTAssertEqual(client.getBooleanDetails(key: "flag", defaultValue: true).error, .invalidContext)
        XCTAssertEqual(server.options, [false, true], "Invalid context never reaches the network")

        try core.flushAndTearDown()
        let exposures = core.waitAndReturnEvents(ofFeature: FlagsFeature.name, ofType: ExposureEvent.self)
        let evaluations = core.waitAndReturnEvents(ofFeature: FlagsEvaluationFeature.name, ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(exposures.count, mode == .immediate ? 1 : 2, "Future mode preserves exposures for older allocations")
        if suppressTelemetry {
            XCTAssertTrue(evaluations.isEmpty, "The independent telemetry option suppresses evaluations and retains exposures")
            return
        }
        XCTAssertFalse(evaluations.isEmpty, "Experimentation opt-out does not disable evaluation telemetry")
        let rejected = try XCTUnwrap(evaluations.first { $0.flag.key == "flag" && $0.error?.message == "INVALID_CONTEXT" })
        XCTAssertEqual(rejected.targetingKey, "subject")
        for key in ["flag", "string", "integer", "double", "object"] {
            let evaluation = try XCTUnwrap(evaluations.first { $0.flag.key == key && $0.allocation?.key == "ordinary" })
            XCTAssertNil(evaluation.error)
            XCTAssertNil(evaluation.runtimeDefaultUsed)
            XCTAssertEqual(evaluation.targetingKey, "subject")
            XCTAssertEqual(evaluation.evaluationCount, 1)
        }
        if mode == .futureExperimentsOnly {
            let evaluation = try XCTUnwrap(evaluations.first { $0.flag.key == "older" })
            XCTAssertNil(evaluation.error)
            XCTAssertNil(evaluation.runtimeDefaultUsed)
            XCTAssertEqual(evaluation.allocation?.key, "older-experiment")
            XCTAssertEqual(evaluation.evaluationCount, 1)
        }
    }

    private enum Fixtures {
        static let flagsData = FlagsData(
            flags: [
                "test-flag": .init(
                    allocationKey: "allocation-123",
                    variationKey: "variation-123",
                    variation: .boolean(true),
                    reason: "TARGETING_MATCH",
                    doLog: true
                )
            ],
            context: .init(
                targetingKey: "user-123",
                attributes: [:]
            ),
            date: .mockAny()
        )
    }

    func testFirstFlagsFromPersistentStoreLogsOnlyExplicitEvaluation() throws {
        let core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
        defer { try? core.flushAndTearDown() }
        Flags.enable(with: .init(trackEvaluations: true), in: core)
        let scope = core.scope(for: FlagsFeature.self)
        scope.flagsDataStore.setFlagsData(Fixtures.flagsData, forClientNamed: FlagsClient.defaultName)
        scope.dataStore.flush()
        let client = FlagsClient.create(in: core)
        let delivered = expectation(description: "first flags")
        client.onFirstFlags { event in
            XCTAssertEqual(event.flagsChanged, ["test-flag"])
            XCTAssertEqual(FlagsClient.shared(in: core).getBooleanDetails(key: "test-flag", defaultValue: false).value, true)
            delivered.fulfill()
        }
        wait(for: [delivered], timeout: 5)
        client.onFirstFlags { XCTAssertEqual($0.flagsChanged, ["test-flag"]) }
        try core.flushAndTearDown()
        let events = core.waitAndReturnEvents(ofFeature: FlagsEvaluationFeature.name, ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events.first?.evaluationCount, 1)
        XCTAssertEqual(events.first?.flag.key, "test-flag")
    }

    func testNetworkFirstFlagsDoesNotBlockContextUpdate() throws {
        let handlerEntered = ReadWriteLock(wrappedValue: false)
        let handlerReturned = ReadWriteLock(wrappedValue: false)
        let calls = ReadWriteLock(wrappedValue: 0)
        let responseBWritten = DispatchSemaphore(value: 0)
        let contextBCompleted = DispatchSemaphore(value: 0)
        let responseBSent = expectation(description: "B response sent while handler waits")
        let contextBDone = expectation(description: "B context completed")
        let handlerDone = expectation(description: "first flags handler returned")
        let ready = expectation(description: "loopback server ready")
        let assignment = try XCTUnwrap(Fixtures.flagsData.flags["test-flag"])
        let responses = try ["A", "B"].map { key in
            try JSONEncoder().encode(FlagAssignmentsResponse(flags: [key: assignment]))
        }
        let server = try FirstFlagsLoopbackServer { body in
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
            let data = try XCTUnwrap(json["data"] as? [String: Any])
            let attributes = try XCTUnwrap(data["attributes"] as? [String: Any])
            let subject = try XCTUnwrap(attributes["subject"] as? [String: Any])
            let key = try XCTUnwrap(subject["targeting_key"] as? String)
            XCTAssertTrue(key == "A" || key == "B")
            if key == "B" {
                XCTAssertTrue(handlerEntered.wrappedValue)
                XCTAssertFalse(handlerReturned.wrappedValue)
            }
            return (responses[key == "A" ? 0 : 1], key == "B")
        }
        defer { server.stop() }
        server.start(ready: ready) {
            XCTAssertTrue(handlerEntered.wrappedValue)
            XCTAssertFalse(handlerReturned.wrappedValue)
            print("firstFlags regression: B response sent while handler waits")
            responseBSent.fulfill()
            responseBWritten.signal()
        }
        wait(for: [ready], timeout: 5)
        let endpoint = try XCTUnwrap(server.endpoint)
        let core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
        defer { try? core.flushAndTearDown() }
        Flags.enable(with: .init(customFlagsEndpoint: endpoint), in: core)
        // A unique client name guarantees that the first installation comes from the network.
        let client = ReadWriteLock(wrappedValue: FlagsClient.create(name: UUID().uuidString, in: core))
        let cancelled = client.wrappedValue.onFirstFlags { _ in XCTFail("Cancelled registration delivered") }
        cancelled.cancel()
        let subscription = client.wrappedValue.onFirstFlags { event in
            calls.mutate { $0 += 1 }
            XCTAssertEqual(event.flagsChanged, ["A"])
            handlerEntered.wrappedValue = true
            client.wrappedValue.setEvaluationContext(.init(targetingKey: "B")) { result in
                if case .failure(let error) = result { XCTFail("B failed: \(error)") }
                print("firstFlags regression: B completion arrived; handler returned = \(handlerReturned.wrappedValue)")
                contextBCompleted.signal()
                contextBDone.fulfill()
            }
            // B's response can arrive, but its URLSession completion cannot run if this
            // handler still occupies that session's serial completion queue.
            // Keep the handler alive until the fixture confirms its write, even if the
            // client's completion outruns the server's send-completion scheduling.
            XCTAssertEqual(responseBWritten.wait(timeout: .now() + 5), .success)
            let completedWhileWaiting = contextBCompleted.wait(timeout: .now() + 5)
            print("firstFlags regression: B completion during handler = \(completedWhileWaiting)")
            XCTAssertEqual(completedWhileWaiting, .success)
            XCTAssertEqual(client.wrappedValue.getBooleanDetails(key: "B", defaultValue: false).value, true)
            handlerReturned.wrappedValue = true
            handlerDone.fulfill()
        }
        defer { subscription.cancel() }
        client.wrappedValue.setEvaluationContext(.init(targetingKey: "A")) { result in
            if case .failure(let error) = result { XCTFail("A failed: \(error)") }
        }
        // On the unfixed implementation the bounded handler wait expires, allowing B to
        // drain and cleanup to finish instead of leaving a deadlocked simulator process.
        wait(for: [responseBSent, contextBDone, handlerDone], timeout: 12)
        XCTAssertEqual(calls.wrappedValue, 1)
        XCTAssertTrue(client.wrappedValue.getBooleanValue(key: "B", defaultValue: false))
        let replayed = ReadWriteLock(wrappedValue: false)
        client.wrappedValue.onFirstFlags { event in
            XCTAssertEqual(event.flagsChanged, ["A"])
            replayed.wrappedValue = true
        }
        XCTAssertTrue(replayed.wrappedValue)
    }

    // MARK: - EVALLOG.4: Shutdown Flush

    /// EVALLOG.4: Evaluations are flushed when SDK shuts down via flushAndTearDown()
    func testGivenPendingEvaluations_whenSDKShutsDown_itFlushes() throws {
        // Given
        let core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
        Flags.enable(with: .init(trackEvaluations: true), in: core)

        let featureScope = core.scope(for: FlagsFeature.self)
        featureScope.flagsDataStore.setFlagsData(Fixtures.flagsData, forClientNamed: FlagsClient.defaultName)
        featureScope.dataStore.flush()

        let client = FlagsClient.create(in: core)

        // When
        _ = client.getBooleanValue(key: "test-flag", defaultValue: false)

        // Then
        try core.flushAndTearDown()

        let events = core.waitAndReturnEvents(
            ofFeature: FlagsEvaluationFeature.name,
            ofType: FlagEvaluationEvent.self
        )

        XCTAssertEqual(events.count, 1, "Should have flushed pending evaluations on shutdown")
        XCTAssertEqual(events.first?.flag.key, "test-flag")
    }

    func testNamedClientsKeepIndependentConfigurationAndOriginalConfigurationOnReuse() throws {
        let core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
        defer { try? core.flushAndTearDown() }
        Flags.enable(in: core)
        let optedOut = FlagsClient.create(configuration: .init(enableEvaluationTelemetryOptOutParameter: true), name: "opted-out", in: core)
        let reused = FlagsClient.create(configuration: .init(enableEvaluationTelemetryOptOutParameter: false), name: "opted-out", in: core)
        let normal = FlagsClient.create(name: "normal", in: core)
        XCTAssertIdentical(optedOut, reused)
        let assignment = try XCTUnwrap(Fixtures.flagsData.flags["test-flag"])
        let context = FlagsEvaluationContext(targetingKey: "user", attributes: ["dd_evaluation_telemetry_opt_out": .bool(true)])
        try XCTUnwrap(reused as? FlagsClientInternal).sendFlagEvaluation(key: "suppressed", assignment: assignment, context: context)
        try XCTUnwrap(normal as? FlagsClientInternal).sendFlagEvaluation(key: "normal", assignment: assignment, context: context)
        core.flush()
        let evaluations = core.waitAndReturnEvents(ofFeature: FlagsEvaluationFeature.name, ofType: FlagEvaluationEvent.self)
        XCTAssertEqual(evaluations.map(\.flag.key), ["normal"])
        let exposures = core.waitAndReturnEvents(ofFeature: FlagsFeature.name, ofType: ExposureEvent.self)
        XCTAssertEqual(exposures.count, 2)
    }
}

/// Exercises native assignment loading and telemetry uploads over a loopback HTTP connection.
final class FlagsEvaluationLocalIntakeTests: XCTestCase {
    @MainActor
    func testSubjectSwitchDoesNotUploadPreviousSubjectsOptedOutEvaluations() throws {
        let ready = expectation(description: "local intake ready")
        let server = try FlagsLocalIntake(ready: ready)
        server.start()
        wait(for: [ready], timeout: 5)
        defer { server.stop() }
        let instanceName = "flags-subject-switch-\(UUID().uuidString)"
        let core = Datadog.initialize(
            with: .init(clientToken: "local-intake-token", env: "local-test"),
            trackingConsent: .granted,
            instanceName: instanceName
        )
        defer { Datadog.internalFlushAndDeinitialize(instanceName: instanceName) }
        RUM.enable(with: .init(applicationID: UUID().uuidString, customEndpoint: try server.url("rum")), in: core)
        Flags.enable(
            with: .init(
                customFlagsEndpoint: try server.url("assignments"),
                customExposureEndpoint: try server.url("exposures"),
                customEvaluationEndpoint: try server.url("evaluations")
            ),
            in: core
        )
        let client = FlagsClient.create(configuration: .init(enableEvaluationTelemetryOptOutParameter: true), in: core)
        let nativeCore = try XCTUnwrap(core as? DatadogCore)
        let monitor = RUMMonitor.shared(in: core)
        let loaded = expectation(description: "A loaded")
        client.setEvaluationContext(localContext(optOut: true, subject: "A")) { _ in loaded.fulfill() }
        wait(for: [loaded], timeout: 5)
        let received = expectation(description: "B request held")
        server.holdAssignments(onRequest: { received.fulfill() })
        let refreshed = expectation(description: "B loaded")
        client.setEvaluationContext(localContext(optOut: false, subject: "B")) { _ in refreshed.fulfill() }
        wait(for: [received], timeout: 5)

        monitor.startView(key: "A", name: "A pending switch")
        XCTAssertTrue(client.getBooleanValue(key: "hidden-flag", defaultValue: false))
        nativeCore.flush()
        monitor.stopView(key: "A")
        nativeCore.flushAndUpload()
        XCTAssertTrue(try server.events(at: "evaluations").isEmpty)
        XCTAssertFalse(try server.events(at: "rum").contains { ($0["feature_flags"] as? [String: Any])?["hidden-flag"] != nil })
        XCTAssertEqual(try server.events(at: "exposures").count, 1)

        server.releaseAssignments(status: 200)
        wait(for: [refreshed], timeout: 5)
        monitor.startView(key: "B", name: "B ready")
        XCTAssertTrue(client.getBooleanValue(key: "visible-flag", defaultValue: false))
        nativeCore.flush()
        monitor.stopView(key: "B")
        nativeCore.flushAndUpload()
        let evaluations = try server.events(at: "evaluations").flatMap { $0["flagEvaluations"] as? [[String: Any]] ?? [] }
        XCTAssertEqual(evaluations.compactMap { ($0["flag"] as? [String: Any])?["key"] as? String }, ["visible-flag"])
        XCTAssertTrue(try server.events(at: "rum").contains { ($0["feature_flags"] as? [String: Any])?["visible-flag"] != nil })
        XCTAssertEqual(try server.events(at: "exposures").count, 2)
    }

    @MainActor
    func testWhenOptedOut_itPreservesExposureAndRUMWithoutEvaluationTelemetry() throws {
        try runLocalIntake(enabled: true, optOut: true)
    }

    @MainActor
    func testWhenActivationIsDisabled_trueAttributePreservesEvaluationTelemetry() throws {
        try runLocalIntake(enabled: false, optOut: true)
    }

    @MainActor
    func testWhenOptOutIsFalse_itPreservesEvaluationTelemetry() throws {
        try runLocalIntake(enabled: true, optOut: false)
    }

    @MainActor
    func testTelemetryAttributeTargetsAssignmentsAndPreservesExposureDeduplication() throws {
        for enabled in [false, true] {
            let ready = expectation(description: "targeting intake ready")
            let server = try FlagsLocalIntake(ready: ready)
            server.start()
            wait(for: [ready], timeout: 5)
            defer { server.stop() }
            let instanceName = "flags-targeting-\(UUID().uuidString)"
            let core = Datadog.initialize(with: .init(clientToken: "local-intake-token", env: "local-test"), trackingConsent: .granted, instanceName: instanceName)
            defer { Datadog.internalFlushAndDeinitialize(instanceName: instanceName) }
            Flags.enable(with: .init(customFlagsEndpoint: try server.url("assignments"), customExposureEndpoint: try server.url("exposures"), customEvaluationEndpoint: try server.url("evaluations")), in: core)
            let client = FlagsClient.create(configuration: .init(enableEvaluationTelemetryOptOutParameter: enabled), in: core)

            for (index, optOut) in [false, true, true, false].enumerated() {
                let loaded = expectation(description: "targeted assignment loaded")
                client.setEvaluationContext(localContext(optOut: optOut)) { result in
                    if case .failure(let error) = result { XCTFail("Assignment load failed: \(error)") }
                    loaded.fulfill()
                }
                wait(for: [loaded], timeout: 5)
                let details = client.getBooleanDetails(key: "targeting-flag", defaultValue: !optOut)
                XCTAssertEqual(details.value, optOut)
                XCTAssertEqual(details.variant, String(optOut))
                XCTAssertEqual(details.allocationKey, "targeted-allocation")
                XCTAssertEqual(details.reason, "TARGETING_MATCH")
                if index < 2 {
                    XCTAssertEqual(client.getBooleanValue(key: "targeting-flag", defaultValue: !optOut), optOut)
                }
            }
            Datadog.internalFlushAndDeinitialize(instanceName: instanceName)
            let exposures = try server.events(at: "exposures")
            let exposedValues = try exposures.map { exposure in
                let subject = try XCTUnwrap(exposure["subject"] as? [String: Any])
                let attributes = try XCTUnwrap(subject["attributes"] as? [String: Any])
                return try XCTUnwrap(attributes["dd_evaluation_telemetry_opt_out"] as? Bool)
            }
            XCTAssertEqual(exposedValues, [false, true, false])
            let evaluations = try server.events(at: "evaluations").flatMap { $0["flagEvaluations"] as? [[String: Any]] ?? [] }
            let evaluationCount = evaluations.reduce(0) { $0 + ($1["evaluation_count"] as? Int ?? 0) }
            XCTAssertEqual(evaluationCount, enabled ? 3 : 6)
            XCTAssertEqual(server.requests.filter { $0.url?.path == "/assignments" }.count, 4)
            print("Local targeting intake: enabled=\(enabled), assignments=4, exposures=3, evaluations=\(evaluationCount)")
        }
    }

    @MainActor
    private func runLocalIntake(enabled: Bool, optOut: Bool) throws {
        let ready = expectation(description: "local intake ready")
        let server = try FlagsLocalIntake(ready: ready)
        server.start()
        wait(for: [ready], timeout: 5)
        defer { server.stop() }

        let instanceName = "flags-opt-out-\(UUID().uuidString)"
        let core = Datadog.initialize(
            with: .init(clientToken: "local-intake-token", env: "local-test"),
            trackingConsent: .granted,
            instanceName: instanceName
        )
        defer { Datadog.internalFlushAndDeinitialize(instanceName: instanceName) }
        RUM.enable(with: .init(applicationID: UUID().uuidString, customEndpoint: try server.url("rum")), in: core)
        Flags.enable(
            with: .init(
                customFlagsEndpoint: try server.url("assignments"),
                customExposureEndpoint: try server.url("exposures"),
                customEvaluationEndpoint: try server.url("evaluations")
            ),
            in: core
        )
        let client = FlagsClient.create(configuration: .init(enableEvaluationTelemetryOptOutParameter: enabled), in: core)
        let loaded = expectation(description: "assignments loaded")
        client.setEvaluationContext(.init(targetingKey: "local-user", attributes: ["dd_evaluation_telemetry_opt_out": .bool(optOut)])) { result in
            if case .failure(let error) = result { XCTFail("Assignment load failed: \(error)") }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
        XCTAssertEqual(client.state.currentState, .ready)

        let monitor = RUMMonitor.shared(in: core)
        monitor.startView(key: "local-view", name: "Local View")
        let details = client.getBooleanDetails(key: "local-flag", defaultValue: false)
        XCTAssertEqual(details.value, true)
        XCTAssertEqual(details.variant, "enabled")
        XCTAssertEqual(details.allocationKey, "allocation")
        XCTAssertEqual(client.getBooleanDetails(key: "missing", defaultValue: false).error, .flagNotFound)
        XCTAssertEqual(client.getStringDetails(key: "local-flag", defaultValue: "default").error, .typeMismatch)
        try XCTUnwrap(core as? DatadogCore).flush()
        monitor.addError(message: "unrelated application error")
        monitor.stopView(key: "local-view")
        Datadog.internalFlushAndDeinitialize(instanceName: instanceName)

        let assignments = server.requests.filter { $0.url?.path == "/assignments" }
        let exposures = try server.events(at: "exposures")
        let rum = try server.events(at: "rum")
        let evaluations = try server.events(at: "evaluations").flatMap { $0["flagEvaluations"] as? [[String: Any]] ?? [] }
        XCTAssertEqual(assignments.count, 1)
        XCTAssertEqual(exposures.count, 1)
        XCTAssertTrue(rum.contains { $0["type"] as? String == "view" })
        XCTAssertTrue(rum.contains { $0["type"] as? String == "error" })
        print("Local intake: enabled=\(enabled), optOut=\(optOut), assignments=\(assignments.count), exposures=\(exposures.count), evaluations=\(evaluations.count), RUM=\(rum.count)")
        XCTAssertEqual(evaluations.count, enabled && optOut ? 0 : 3)
        XCTAssertEqual(rum.contains { ($0["feature_flags"] as? [String: Any])?["local-flag"] != nil }, !(enabled && optOut))
        let requestBody = try XCTUnwrap(assignments.first?.httpBody)
        let serializedContext = String(decoding: requestBody, as: UTF8.self)
        XCTAssertTrue(serializedContext.contains("dd_evaluation_telemetry_opt_out"))
        let exposureSubject = try XCTUnwrap(exposures.first?["subject"] as? [String: Any])
        let exposureAttributes = try XCTUnwrap(exposureSubject["attributes"] as? [String: Any])
        XCTAssertEqual(exposureAttributes["dd_evaluation_telemetry_opt_out"] as? Bool, optOut)
    }

    @MainActor
    func testCurrentTelemetryContextDuringPendingAndFailedAssignments() throws {
        let ready = expectation(description: "local intake ready")
        let server = try FlagsLocalIntake(ready: ready)
        server.start()
        wait(for: [ready], timeout: 5)
        defer { server.stop() }
        let instanceName = "flags-transitions-\(UUID().uuidString)"
        let core = Datadog.initialize(with: .init(clientToken: "local-intake-token", env: "local-test"), trackingConsent: .granted, instanceName: instanceName)
        defer { Datadog.internalFlushAndDeinitialize(instanceName: instanceName) }
        RUM.enable(with: .init(applicationID: UUID().uuidString, customEndpoint: try server.url("rum")), in: core)
        Flags.enable(with: .init(customFlagsEndpoint: try server.url("assignments"), customExposureEndpoint: try server.url("exposures"), customEvaluationEndpoint: try server.url("evaluations")), in: core)
        let client = FlagsClient.create(configuration: .init(enableEvaluationTelemetryOptOutParameter: true), in: core)
        let monitor = RUMMonitor.shared(in: core)
        let nativeCore = try XCTUnwrap(core as? DatadogCore)
        let received = expectation(description: "assignment request held")
        server.holdAssignments(onRequest: { received.fulfill() })
        let loaded = expectation(description: "late assignment completes")
        client.setEvaluationContext(localContext(optOut: false)) { result in
            if case .failure(let error) = result { XCTFail("Assignment load failed: \(error)") }
            loaded.fulfill()
        }
        wait(for: [received], timeout: 5)
        let optedOutRequest = expectation(description: "opt-out refresh held")
        server.holdAssignments(onRequest: { optedOutRequest.fulfill() })
        let optedOutLoaded = expectation(description: "opt-out refresh completes")
        client.setEvaluationContext(localContext(optOut: true)) { _ in optedOutLoaded.fulfill() }
        wait(for: [optedOutRequest], timeout: 5)
        XCTAssertEqual(client.getBooleanDetails(key: "pending-default", defaultValue: false).error, .providerNotReady)
        server.releaseAssignments(status: 200)
        wait(for: [loaded, optedOutLoaded], timeout: 5)

        monitor.startView(key: "hidden", name: "Hidden")
        XCTAssertTrue(client.getBooleanValue(key: "hidden-flag", defaultValue: false))
        nativeCore.flush()
        monitor.stopView(key: "hidden")
        nativeCore.flushAndUpload()
        XCTAssertTrue(try server.events(at: "evaluations").isEmpty)
        XCTAssertEqual(server.requests.filter { $0.url?.path == "/assignments" }.count, 2)

        let optedInLoaded = expectation(description: "opt-in refresh completes")
        client.setEvaluationContext(localContext(optOut: false)) { _ in optedInLoaded.fulfill() }
        wait(for: [optedInLoaded], timeout: 5)
        monitor.startView(key: "visible", name: "Visible")
        XCTAssertTrue(client.getBooleanValue(key: "visible-flag", defaultValue: false))
        nativeCore.flush()
        monitor.stopView(key: "visible")
        // A later opt-out must not purge the evaluation already queued above.
        let optedOutAgainReceived = expectation(description: "second opt-out refresh held")
        server.holdAssignments(onRequest: { optedOutAgainReceived.fulfill() })
        let optedOutAgainFailed = expectation(description: "second opt-out refresh fails")
        client.setEvaluationContext(localContext(optOut: true)) { _ in optedOutAgainFailed.fulfill() }
        wait(for: [optedOutAgainReceived], timeout: 5)
        monitor.startView(key: "hidden-again", name: "Hidden Again")
        XCTAssertTrue(client.getBooleanValue(key: "hidden-again-flag", defaultValue: false))
        nativeCore.flush()
        monitor.addError(message: "unrelated application error")
        monitor.stopView(key: "hidden-again")
        server.releaseAssignments(status: 500)
        wait(for: [optedOutAgainFailed], timeout: 5)
        XCTAssertEqual(client.getBooleanDetails(key: "failed-opt-out-default", defaultValue: false).error, .providerNotReady)
        nativeCore.flushAndUpload()
        XCTAssertEqual(server.requests.filter { $0.url?.path == "/assignments" }.count, 4)

        let failingRequest = expectation(description: "new subject request held")
        server.holdAssignments(onRequest: { failingRequest.fulfill() })
        let failed = expectation(description: "assignment failure delivered")
        client.setEvaluationContext(localContext(optOut: true, subject: "other-user")) { result in
            if case .success = result { XCTFail("Expected assignment failure") }
            failed.fulfill()
        }
        wait(for: [failingRequest], timeout: 5)
        server.releaseAssignments(status: 500)
        wait(for: [failed], timeout: 5)
        XCTAssertEqual(client.state.currentState, .error)
        XCTAssertEqual(client.getBooleanDetails(key: "failed-default", defaultValue: false).error, .providerNotReady)
        let resumedRequest = expectation(description: "opt-in request held")
        server.holdAssignments(onRequest: { resumedRequest.fulfill() })
        let resumedFailed = expectation(description: "opt-in refresh fails")
        client.setEvaluationContext(localContext(optOut: false, subject: "other-user")) { _ in resumedFailed.fulfill() }
        wait(for: [resumedRequest], timeout: 5)
        XCTAssertEqual(client.getBooleanDetails(key: "resumed-default", defaultValue: false).error, .providerNotReady)
        server.releaseAssignments(status: 500)
        wait(for: [resumedFailed], timeout: 5)
        Datadog.internalFlushAndDeinitialize(instanceName: instanceName)

        let evaluations = try server.events(at: "evaluations").flatMap { $0["flagEvaluations"] as? [[String: Any]] ?? [] }
        let keys = evaluations.compactMap { ($0["flag"] as? [String: Any])?["key"] as? String }
        XCTAssertEqual(keys.sorted(), ["resumed-default", "visible-flag"])
        XCTAssertEqual(try server.events(at: "exposures").count, 3)
        XCTAssertEqual(server.requests.filter { $0.url?.path == "/assignments" }.count, 6)
        let rum = try server.events(at: "rum")
        XCTAssertTrue(rum.contains { ($0["feature_flags"] as? [String: Any])?["visible-flag"] != nil })
        XCTAssertFalse(rum.contains { ($0["feature_flags"] as? [String: Any])?["hidden-flag"] != nil || ($0["feature_flags"] as? [String: Any])?["hidden-again-flag"] != nil })
        XCTAssertTrue(rum.contains { $0["type"] as? String == "error" })
        print("Local transition intake: assignments=6, exposures=3, evaluation keys=\(keys.sorted())")
    }

    private func localContext(optOut: Bool, subject: String = "local-user") -> FlagsEvaluationContext {
        .init(targetingKey: subject, attributes: ["dd_evaluation_telemetry_opt_out": .bool(optOut)])
    }

    @MainActor
    func testCachedAssignmentsUseFullContextAcrossActivationChanges() throws {
        for initialEnabled in [false, true] {
            try runCachedAssignments(initialEnabled: initialEnabled)
        }
    }

    @MainActor
    private func runCachedAssignments(initialEnabled: Bool) throws {
        let ready = expectation(description: "local intake ready")
        let server = try FlagsLocalIntake(ready: ready)
        server.start()
        wait(for: [ready], timeout: 5)
        defer { server.stop() }
        let instanceName = "flags-cache-\(UUID().uuidString)"
        defer { Datadog.internalFlushAndDeinitialize(instanceName: instanceName) }

        func makeCore() throws -> DatadogCoreProtocol {
            let core = Datadog.initialize(with: .init(clientToken: "local-intake-token", env: "local-test"), trackingConsent: .granted, instanceName: instanceName)
            Flags.enable(with: .init(customFlagsEndpoint: try server.url("assignments"), customExposureEndpoint: try server.url("exposures"), customEvaluationEndpoint: try server.url("evaluations")), in: core)
            return core
        }

        let initialCore = try makeCore()
        let initialClient = FlagsClient.create(configuration: .init(enableEvaluationTelemetryOptOutParameter: initialEnabled), in: initialCore)
        let loaded = expectation(description: "initial assignments loaded")
        initialClient.setEvaluationContext(localContext(optOut: true)) { result in
            if case .failure(let error) = result { XCTFail("Assignment load failed: \(error)") }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
        Datadog.internalFlushAndDeinitialize(instanceName: instanceName)

        let restartedCore = try makeCore()
        let restartedEnabled = !initialEnabled
        let cachedClient = FlagsClient.create(configuration: .init(enableEvaluationTelemetryOptOutParameter: restartedEnabled), in: restartedCore)
        let cached = cachedClient.getBooleanDetails(key: "local-flag", defaultValue: false)
        XCTAssertTrue(cached.value)
        XCTAssertEqual(cached.reason, "CACHED")
        let received = expectation(description: "cached refresh received")
        server.holdAssignments(onRequest: { received.fulfill() })
        let failed = expectation(description: "cached refresh failed")
        cachedClient.setEvaluationContext(localContext(optOut: true)) { result in
            if case .success = result { XCTFail("Expected refresh failure") }
            failed.fulfill()
        }
        wait(for: [received], timeout: 5)
        server.releaseAssignments(status: 500)
        wait(for: [failed], timeout: 5)
        XCTAssertEqual(cachedClient.state.currentState, .stale)
        let hidden = cachedClient.getBooleanDetails(key: "hidden-flag", defaultValue: false)
        XCTAssertTrue(hidden.value)
        XCTAssertEqual(hidden.reason, "CACHED")
        XCTAssertEqual(hidden.variant, "enabled")
        try XCTUnwrap(restartedCore as? DatadogCore).flushAndUpload()
        let cachedEvaluations = try server.events(at: "evaluations").flatMap { $0["flagEvaluations"] as? [[String: Any]] ?? [] }
        XCTAssertEqual(cachedEvaluations.count, restartedEnabled ? 0 : 2)

        let changedReceived = expectation(description: "changed cached context request received")
        server.holdAssignments(onRequest: { changedReceived.fulfill() })
        let changedFailed = expectation(description: "changed cached context refresh failed")
        cachedClient.setEvaluationContext(localContext(optOut: false)) { result in
            if case .success = result { XCTFail("Expected refresh failure") }
            changedFailed.fulfill()
        }
        wait(for: [changedReceived], timeout: 5)
        XCTAssertEqual(cachedClient.state.currentState, .reconciling)
        // Disk assignments cannot serve a different targeting context before a successful fetch.
        let pending = cachedClient.getBooleanDetails(key: "visible-flag", defaultValue: false)
        XCTAssertFalse(pending.value)
        XCTAssertEqual(pending.error, .providerNotReady)
        XCTAssertNil(pending.reason)
        XCTAssertNil(pending.variant)
        server.releaseAssignments(status: 500)
        wait(for: [changedFailed], timeout: 5)
        XCTAssertEqual(cachedClient.state.currentState, .error)
        XCTAssertEqual(cachedClient.getBooleanDetails(key: "failed-default", defaultValue: false).error, .providerNotReady)
        Datadog.internalFlushAndDeinitialize(instanceName: instanceName)
        let evaluations = try server.events(at: "evaluations").flatMap { $0["flagEvaluations"] as? [[String: Any]] ?? [] }
        XCTAssertEqual(evaluations.count, restartedEnabled ? 2 : 4)
        let keys = evaluations.compactMap { ($0["flag"] as? [String: Any])?["key"] as? String }
        XCTAssertTrue(keys.contains("visible-flag"))
        XCTAssertTrue(keys.contains("failed-default"))
        let exposures = try server.events(at: "exposures")
        XCTAssertEqual(exposures.count, 2)
        for exposure in exposures {
            let subject = try XCTUnwrap(exposure["subject"] as? [String: Any])
            let attributes = try XCTUnwrap(subject["attributes"] as? [String: Any])
            XCTAssertEqual(attributes["dd_evaluation_telemetry_opt_out"] as? Bool, true)
        }
        XCTAssertEqual(server.requests.filter { $0.url?.path == "/assignments" }.count, 3)
        print("Local cache intake: initialEnabled=\(initialEnabled), assignments=3, exposures=2, evaluations=\(evaluations.count), state=error")
    }
}

private final class FlagsLocalIntake {
    private let listener: NWListener
    private let ready: XCTestExpectation
    private let queue = DispatchQueue(label: "flags-local-intake")
    private var connections: [NWConnection] = []
    private var received: [URLRequest] = []
    private var onHeldAssignment: (() -> Void)?
    private var heldAssignments: [(NWConnection, URLRequest)] = []

    var requests: [URLRequest] { queue.sync { received } }

    init(ready: XCTestExpectation) throws {
        self.ready = ready
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() {
        listener.stateUpdateHandler = { [weak self] state in
            if case .ready = state { self?.ready.fulfill() }
            if case .failed(let error) = state { XCTFail("Local intake failed: \(error)") }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            connections.append(connection)
            connection.start(queue: queue)
            receive(connection, buffered: Data())
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.sync {
            connections.forEach { $0.cancel() }
            connections.removeAll()
            listener.cancel()
        }
    }

    func url(_ path: String) throws -> URL {
        let port = try XCTUnwrap(listener.port)
        return try XCTUnwrap(URL(string: "http://127.0.0.1:\(port.rawValue)/\(path)"))
    }

    func events(at path: String) throws -> [[String: Any]] {
        try requests.filter { $0.url?.path == "/\(path)" }.flatMap { request in
            let body = try XCTUnwrap(request.decompressed().httpBody)
            return try body.split(separator: 0x0A).map { line in
                try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line)) as? [String: Any])
            }
        }
    }

    func holdAssignments(onRequest: @escaping () -> Void) {
        queue.sync { onHeldAssignment = onRequest }
    }

    func releaseAssignments(status: Int) {
        queue.sync {
            onHeldAssignment = nil
            for (connection, request) in heldAssignments {
                respond(connection, request: request, status: status)
            }
            heldAssignments.removeAll()
        }
    }

    private func respond(_ connection: NWConnection, request: URLRequest, status: Int = 200) {
        do {
            let body: Data
            if request.url?.path == "/assignments" {
                let assignment = FlagAssignment(allocationKey: "allocation", variationKey: "enabled", variation: .boolean(true), reason: "TARGETING_MATCH", doLog: true)
                let keys = ["local-flag", "hidden-flag", "visible-flag", "hidden-again-flag"]
                var assignments = Dictionary(uniqueKeysWithValues: keys.map { ($0, assignment) })
                let requestJSON = try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any]
                let data = requestJSON?["data"] as? [String: Any]
                let attributes = data?["attributes"] as? [String: Any]
                let subject = attributes?["subject"] as? [String: Any]
                let targetingAttributes = subject?["targeting_attributes"] as? [String: Any]
                let target = targetingAttributes?["dd_evaluation_telemetry_opt_out"] as? Bool ?? false
                assignments["targeting-flag"] = .init(allocationKey: "targeted-allocation", variationKey: String(target), variation: .boolean(target), reason: "TARGETING_MATCH", doLog: true)
                body = try JSONEncoder().encode(FlagAssignmentsResponse(flags: assignments))
            } else {
                body = Data("{}".utf8)
            }
            let response = "HTTP/1.1 \(status) Response\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(response.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        } catch {
            XCTFail("Local intake could not encode assignments: \(error)")
            connection.cancel()
        }
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, complete, error in
            guard let self else {
                return
            }
            let bytes = buffered + (data ?? Data())
            guard let separator = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                if !complete && error == nil { receive(connection, buffered: bytes) }
                return
            }
            let headers = String(decoding: bytes[..<separator.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
            let length = headers.first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) } ?? 0
            guard bytes.count >= separator.upperBound + length else {
                if !complete && error == nil { receive(connection, buffered: bytes) }
                return
            }
            do {
                let path = try XCTUnwrap(headers.first?.split(separator: " ").dropFirst().first)
                var request = URLRequest(url: try url(String(path.dropFirst())))
                request.httpBody = bytes.subdata(in: separator.upperBound..<(separator.upperBound + length))
                for header in headers.dropFirst() {
                    let pieces = header.split(separator: ":", maxSplits: 1).map(String.init)
                    if pieces.count == 2 { request.setValue(pieces[1].trimmingCharacters(in: .whitespaces), forHTTPHeaderField: pieces[0]) }
                }
                received.append(request)
                let isAssignment = request.url?.path == "/assignments"
                if isAssignment, let onHeldAssignment {
                    heldAssignments.append((connection, request))
                    onHeldAssignment()
                } else {
                    respond(connection, request: request)
                }
            } catch {
                XCTFail("Local intake could not process request: \(error)")
                connection.cancel()
            }
        }
    }
}

private final class OptOutAssignmentsStub {
    private(set) var options: [Bool] = []

    func fetch(_ request: URLRequest, completion: @escaping (Result<Data, Error>) -> Void) {
        do {
            let body = try XCTUnwrap(request.httpBody)
            let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let attributes = (request?["data"] as? [String: Any])?["attributes"] as? [String: Any]
            let mode = (attributes?["evaluation_options"] as? [String: Any])?["experimentation_opt_out_mode"] as? String
            let optedOut = mode == "immediate" || mode == "future_experiments_only"
            self.options.append(optedOut)
            let values: [String: FlagAssignment.Variation] = [
                "flag": .boolean(!optedOut), "string": .string("ordinary"), "integer": .integer(42),
                "double": .double(1.5), "object": .object(.dictionary(["ordinary": .bool(true)]))
            ]
            var flags = values.mapValues { value in
                FlagAssignment(
                    allocationKey: optedOut ? "ordinary" : "experiment",
                    variationKey: "variant",
                    variation: value,
                    reason: "TARGETING_MATCH",
                    doLog: !optedOut
                )
            }
            if mode == "future_experiments_only" {
                flags["older"] = FlagAssignment(
                    allocationKey: "older-experiment",
                    variationKey: "older-variant",
                    variation: .boolean(true),
                    reason: "TARGETING_MATCH",
                    doLog: true
                )
            }
            let response = FlagAssignmentsResponse(
                flags: flags,
                experimentationOptOut: mode == "immediate" ? true : nil,
                experimentationOptOutMode: mode == "future_experiments_only" ? mode : nil,
                experimentationOptOutAt: mode == "future_experiments_only" ? "2099-01-01T00:00:00.123456789Z" : nil
            )
            completion(.success(try JSONEncoder().encode(response)))
        } catch {
            XCTFail("Could not encode assignment fixture: \(error)")
            completion(.failure(error))
        }
    }
}

private final class FirstFlagsLoopbackServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "first-flags.loopback")
    private var connections: [NWConnection] = []
    private let response: (Data) throws -> (Data, Bool)

    var endpoint: URL? {
        listener.port.flatMap { URL(string: "http://127.0.0.1:\($0.rawValue)/precompute-assignments") }
    }

    init(response: @escaping (Data) throws -> (Data, Bool)) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        self.response = response
    }

    func start(ready: XCTestExpectation, responseB: @escaping () -> Void) {
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
            if case .failed(let error) = state { XCTFail("Loopback listener failed: \(error)") }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            self.connections.append(connection)
            connection.start(queue: self.queue)
            self.receive(connection, data: Data(), responseB: responseB)
        }
        listener.start(queue: queue)
    }

    func stop() {
        queue.sync {
            listener.cancel()
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func receive(_ connection: NWConnection, data: Data, responseB: @escaping () -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, complete, error in
            guard let self else {
                return
            }
            var request = data
            request.append(chunk ?? Data())
            guard error == nil, request.count <= 65_536 else {
                XCTFail("Loopback request failed or exceeded fixture limit")
                connection.cancel()
                return
            }
            if let separator = request.range(of: Data("\r\n\r\n".utf8)),
               let header = String(data: request[..<separator.lowerBound], encoding: .utf8),
               let lengthLine = header.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }),
               let length = Int(lengthLine.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)),
               request.count - separator.upperBound >= length {
                do {
                    let body = Data(request[separator.upperBound..<(separator.upperBound + length)])
                    let (payload, isB) = try self.response(body)
                    var reply = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8)
                    reply.append(payload)
                    connection.send(content: reply, completion: .contentProcessed { error in
                        XCTAssertNil(error)
                        if isB { responseB() }
                        connection.cancel()
                    })
                } catch {
                    XCTFail("Invalid Flags request: \(error)")
                    connection.cancel()
                }
            } else if complete {
                XCTFail("Incomplete loopback HTTP request")
                connection.cancel()
            } else {
                self.receive(connection, data: request, responseB: responseB)
            }
        }
    }
}
