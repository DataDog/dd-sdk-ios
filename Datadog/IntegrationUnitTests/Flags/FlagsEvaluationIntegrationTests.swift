/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
import Network

@_spi(Internal)
@testable import DatadogFlags

/// Covers integration scenarios for flag evaluation logging.
final class FlagsEvaluationIntegrationTests: XCTestCase {
    func testImmediateOptOutLoopbackDeliveryAndTelemetry() throws {
        try runOptOutLoopbackDeliveryAndTelemetry(mode: .immediate)
    }

    func testFutureOptOutLoopbackDeliveryAndTelemetry() throws {
        try runOptOutLoopbackDeliveryAndTelemetry(mode: .futureExperimentsOnly)
    }

    private func runOptOutLoopbackDeliveryAndTelemetry(mode: FlagsClient.ExperimentationOptOutMode) throws {
        let server = try OptOutAssignmentServer()
        defer { server.stop() }
        let listening = expectation(description: "loopback listening")
        server.start { listening.fulfill() }
        waitForExpectations(timeout: 5)
        let endpoint = try XCTUnwrap(server.endpoint)
        let core = DatadogCoreProxy(context: .mockWith(trackingConsent: .granted))
        defer { try? core.flushAndTearDown() }
        Flags.enable(with: .init(customFlagsEndpoint: endpoint, evaluationFlushInterval: 60), in: core)
        let client = FlagsClient.create(experimentationOptOutMode: mode, in: core)

        let initial = expectation(description: "eligible response")
        client.setEvaluationContext(.init(targetingKey: "subject")) { result in
            if case .failure(let error) = result { XCTFail("\(error)") }
            initial.fulfill()
        }
        waitForExpectations(timeout: 5)
        XCTAssertTrue(client.getBooleanValue(key: "flag", defaultValue: false))

        let withdrawn = expectation(description: "ordinary fallback")
        client.setEvaluationContext(.init(
            targetingKey: "subject",
            attributes: ["dd_experimentation_opt_out_at": .string("2099-01-01T02:00:00.123456789+02:00")]
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
            targetingKey: "subject", attributes: ["dd_experimentation_opt_out_at": .bool(true)]
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
        XCTAssertFalse(evaluations.isEmpty, "Experimentation opt-out does not disable evaluation telemetry")
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
}

/// Exercises URLSession against a real HTTP listener with deterministic Precompute responses.
private final class OptOutAssignmentServer {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "flags.optout.loopback")
    private var capturedOptions: [Bool] = []
    var options: [Bool] { queue.sync { capturedOptions } }
    var endpoint: URL? {
        listener.port.flatMap { URL(string: "http://127.0.0.1:\($0.rawValue)/precompute-assignments") }
    }

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
    }

    func start(ready: @escaping () -> Void) {
        listener.stateUpdateHandler = { if case .ready = $0 { ready() } }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                return
            }
            connection.start(queue: self.queue)
            self.receive(connection, accumulated: Data())
        }
        listener.start(queue: queue)
    }

    func stop() { listener.cancel() }

    private func receive(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self, error == nil, let data else {
                connection.cancel()
                return
            }
            let accumulated = accumulated + data
            guard let separator = accumulated.range(of: Data("\r\n\r\n".utf8)) else {
                if !complete { self.receive(connection, accumulated: accumulated) }
                return
            }
            let headers = String(decoding: accumulated[..<separator.lowerBound], as: UTF8.self)
            let length = headers
                .components(separatedBy: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            let body = Data(accumulated[separator.upperBound...])
            guard body.count >= length else {
                self.receive(connection, accumulated: accumulated)
                return
            }
            let request = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let attributes = (request?["data"] as? [String: Any])?["attributes"] as? [String: Any]
            let mode = (attributes?["evaluation_options"] as? [String: Any])?["experimentation_opt_out_mode"] as? String
            let optedOut = mode == "immediate" || mode == "future_experiments_only"
            self.capturedOptions.append(optedOut)
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
            guard let payload = try? JSONEncoder().encode(response) else {
                connection.cancel()
                return
            }
            let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(payload.count)\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(header.utf8) + payload, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
