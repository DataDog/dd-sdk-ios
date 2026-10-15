/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import Network
import TestUtilities
import DatadogInternal

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
}

/// Minimal loopback transport fixture: real SDK URLSession requests, no fetch/session mocking.
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
