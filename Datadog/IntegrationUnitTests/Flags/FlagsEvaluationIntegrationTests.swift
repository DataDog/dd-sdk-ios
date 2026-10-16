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
        XCTAssertEqual(serializedContext.contains("dd_evaluation_telemetry_opt_out"), !enabled)
    }

    @MainActor
    func testLocalPolicyTransitionsDuringPendingAndFailedAssignments() throws {
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
        var completed = 0
        client.setEvaluationContext(localContext(optOut: true)) { _ in completed += 1 }
        XCTAssertEqual(completed, 1)
        XCTAssertEqual(client.getBooleanDetails(key: "pending-default", defaultValue: false).error, .providerNotReady)
        server.releaseAssignments(status: 200)
        wait(for: [loaded], timeout: 5)

        monitor.startView(key: "hidden", name: "Hidden")
        XCTAssertTrue(client.getBooleanValue(key: "hidden-flag", defaultValue: false))
        nativeCore.flush()
        monitor.stopView(key: "hidden")
        nativeCore.flushAndUpload()
        XCTAssertTrue(try server.events(at: "evaluations").isEmpty)
        XCTAssertEqual(server.requests.filter { $0.url?.path == "/assignments" }.count, 1)

        client.setEvaluationContext(localContext(optOut: false)) { _ in completed += 1 }
        monitor.startView(key: "visible", name: "Visible")
        XCTAssertTrue(client.getBooleanValue(key: "visible-flag", defaultValue: false))
        nativeCore.flush()
        monitor.stopView(key: "visible")
        // A later opt-out must not purge the evaluation already queued above.
        client.setEvaluationContext(localContext(optOut: true)) { _ in completed += 1 }
        monitor.startView(key: "hidden-again", name: "Hidden Again")
        XCTAssertTrue(client.getBooleanValue(key: "hidden-again-flag", defaultValue: false))
        nativeCore.flush()
        monitor.addError(message: "unrelated application error")
        monitor.stopView(key: "hidden-again")
        nativeCore.flushAndUpload()
        XCTAssertEqual(completed, 3)
        XCTAssertEqual(server.requests.filter { $0.url?.path == "/assignments" }.count, 1)

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
        client.setEvaluationContext(localContext(optOut: false, subject: "other-user")) { _ in completed += 1 }
        XCTAssertEqual(client.getBooleanDetails(key: "resumed-default", defaultValue: false).error, .providerNotReady)
        Datadog.internalFlushAndDeinitialize(instanceName: instanceName)

        let evaluations = try server.events(at: "evaluations").flatMap { $0["flagEvaluations"] as? [[String: Any]] ?? [] }
        let keys = evaluations.compactMap { ($0["flag"] as? [String: Any])?["key"] as? String }
        XCTAssertEqual(keys.sorted(), ["resumed-default", "visible-flag"])
        XCTAssertEqual(try server.events(at: "exposures").count, 3)
        XCTAssertEqual(server.requests.filter { $0.url?.path == "/assignments" }.count, 2)
        let rum = try server.events(at: "rum")
        XCTAssertTrue(rum.contains { ($0["feature_flags"] as? [String: Any])?["visible-flag"] != nil })
        XCTAssertFalse(rum.contains { ($0["feature_flags"] as? [String: Any])?["hidden-flag"] != nil || ($0["feature_flags"] as? [String: Any])?["hidden-again-flag"] != nil })
        XCTAssertTrue(rum.contains { $0["type"] as? String == "error" })
        print("Local transition intake: assignments=2, exposures=3, evaluation keys=\(keys.sorted())")
    }

    private func localContext(optOut: Bool, subject: String = "local-user") -> FlagsEvaluationContext {
        .init(targetingKey: subject, attributes: ["dd_evaluation_telemetry_opt_out": .bool(optOut)])
    }

    @MainActor
    func testCachedAssignmentsKeepLocalPolicyAfterFailedRefresh() throws {
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
        let initialClient = FlagsClient.create(configuration: .init(enableEvaluationTelemetryOptOutParameter: true), in: initialCore)
        let loaded = expectation(description: "initial assignments loaded")
        initialClient.setEvaluationContext(localContext(optOut: false)) { result in
            if case .failure(let error) = result { XCTFail("Assignment load failed: \(error)") }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 5)
        Datadog.internalFlushAndDeinitialize(instanceName: instanceName)

        let restartedCore = try makeCore()
        let cachedClient = FlagsClient.create(configuration: .init(enableEvaluationTelemetryOptOutParameter: true), in: restartedCore)
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
        XCTAssertTrue(try server.events(at: "evaluations").isEmpty)

        var completed = false
        cachedClient.setEvaluationContext(localContext(optOut: false)) { _ in completed = true }
        XCTAssertTrue(completed)
        XCTAssertEqual(cachedClient.state.currentState, .stale)
        XCTAssertEqual(cachedClient.getBooleanDetails(key: "visible-flag", defaultValue: false).reason, "CACHED")
        Datadog.internalFlushAndDeinitialize(instanceName: instanceName)
        let evaluations = try server.events(at: "evaluations").flatMap { $0["flagEvaluations"] as? [[String: Any]] ?? [] }
        XCTAssertEqual(evaluations.count, 1)
        XCTAssertEqual((evaluations.first?["flag"] as? [String: Any])?["key"] as? String, "visible-flag")
        XCTAssertEqual(try server.events(at: "exposures").count, 2)
        XCTAssertEqual(server.requests.filter { $0.url?.path == "/assignments" }.count, 2)
        print("Local cache intake: assignments=2, exposures=2, evaluations=1, state=stale")
    }
}

private final class FlagsLocalIntake {
    private let listener: NWListener
    private let ready: XCTestExpectation
    private let queue = DispatchQueue(label: "flags-local-intake")
    private var connections: [NWConnection] = []
    private var received: [URLRequest] = []
    private var onHeldAssignment: (() -> Void)?
    private var heldAssignments: [NWConnection] = []

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
            for connection in heldAssignments {
                respond(connection, isAssignment: true, status: status)
            }
            heldAssignments.removeAll()
        }
    }

    private func respond(_ connection: NWConnection, isAssignment: Bool, status: Int = 200) {
        do {
            let body: Data
            if isAssignment {
                let assignment = FlagAssignment(allocationKey: "allocation", variationKey: "enabled", variation: .boolean(true), reason: "TARGETING_MATCH", doLog: true)
                let keys = ["local-flag", "hidden-flag", "visible-flag", "hidden-again-flag"]
                body = try JSONEncoder().encode(FlagAssignmentsResponse(flags: Dictionary(uniqueKeysWithValues: keys.map { ($0, assignment) })))
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
                    heldAssignments.append(connection)
                    onHeldAssignment()
                } else {
                    respond(connection, isAssignment: isAssignment)
                }
            } catch {
                XCTFail("Local intake could not process request: \(error)")
                connection.cancel()
            }
        }
    }
}
