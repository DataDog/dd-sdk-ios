/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
import MachO
import DatadogInternal
import TestUtilities

@testable import DatadogProfiling

final class ProfilingQuotaCheckerTests: XCTestCase {
    func testBuildsQuotaURLAndHeaders() throws {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = quotaChecker(for: server)
        let sessionID: UUID = .mockAny()
        let context = DatadogContext.mockWith(
            site: .us1,
            clientToken: "test-client-token",
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionID: sessionID, sessionSampleRate: .maxSampleRate)]
        )

        // When
        _ = checker.receive(message: FeatureMessage.context(context), from: PassthroughCoreMock())
        let request = try XCTUnwrap(server.waitAndReturnRequests(count: 1).first)

        // Then
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://quota.browser-intake-datadoghq.com/api/v2/profiling/quota?session_id=\(sessionID.uuidString.lowercased())"
        )
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.value(forHTTPHeaderField: "DD-CLIENT-TOKEN"), "test-client-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.api+json")
        XCTAssertFalse(request.httpShouldHandleCookies)
    }

    func testDoesNothingWhenContextHasNoRUMSession() {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = quotaChecker(for: server)

        // When
        _ = checker.receive(
            message: FeatureMessage.context(DatadogContext.mockWith(trackingConsent: .granted, additionalContext: [])),
            from: PassthroughCoreMock()
        )

        // Then
        XCTAssertEqual(server.waitAndReturnRequests(count: 0, timeout: 0.1).count, 0)
        XCTAssertNil(checker.quotaResult)
    }

    func testDoesNothingWhenTrackingConsentIsNotGranted() {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = quotaChecker(for: server)

        // When
        [TrackingConsent.pending, .notGranted].forEach { trackingConsent in
            let context = DatadogContext.mockWith(
                trackingConsent: trackingConsent,
                additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
            )

            _ = checker.receive(message: FeatureMessage.context(context), from: PassthroughCoreMock())
        }

        // Then
        XCTAssertEqual(server.waitAndReturnRequests(count: 0, timeout: 0.1).count, 0)
        XCTAssertNil(checker.quotaResult)
    }

    func testDoesNothingWhenRUMSessionIsSampledOut() {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = quotaChecker(for: server)
        let context = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )

        // When
        _ = checker.receive(message: FeatureMessage.context(context), from: PassthroughCoreMock())

        // Then
        XCTAssertEqual(server.waitAndReturnRequests(count: 0, timeout: 0.1).count, 0)
        XCTAssertNil(checker.quotaResult)
    }

    func testStartsQuotaRequestWhenTrackingConsentBecomesGranted() {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = quotaChecker(for: server)
        let rumContext = RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)
        let pendingConsentContext = DatadogContext.mockWith(
            trackingConsent: .pending,
            additionalContext: [rumContext]
        )
        let grantedConsentContext = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [rumContext]
        )

        // When
        _ = checker.receive(message: FeatureMessage.context(pendingConsentContext), from: PassthroughCoreMock())
        _ = checker.receive(message: FeatureMessage.context(grantedConsentContext), from: PassthroughCoreMock())

        // Then
        XCTAssertEqual(server.waitAndReturnRequests(count: 1).count, 1)
    }

    func testDoesNotCheckQuotaWhenContinuousProfilingSamplesOut() {
        // Given: RUM samples in, but its continuous profiling child does not.
        let server = quotaServer()
        let (checker, provider, receiver) = quotaReceiver(for: server, continuousSampleRate: 50)
        let sessionID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-D860B2B9437A")!
        let context = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionID: sessionID, sessionSampleRate: 100)]
        )

        // When
        _ = receiver.receive(message: .context(context), from: PassthroughCoreMock())

        // Then
        XCTAssertEqual(provider.continuousProfilingSampled, false)
        XCTAssertEqual(server.waitAndReturnRequests(count: 0, timeout: 0.1).count, 0)
        XCTAssertNil(checker.quotaResult)
    }

    func testChecksQuotaForAppLaunchWhenContinuousProfilingSamplesOut() {
        // Given: RUM samples in and has an available launch profile, but continuous profiling samples out.
        let server = quotaServer()
        let (_, provider, receiver) = quotaReceiver(
            for: server,
            continuousSampleRate: 50,
            appLaunchSampleRate: 100
        )
        let sessionID = UUID(uuidString: "A1B2C3D4-E5F6-7890-ABCD-D860B2B9437A")!
        let context = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionID: sessionID, sessionSampleRate: 100)]
        )

        // When
        _ = receiver.receive(message: .context(context), from: PassthroughCoreMock())

        // Then
        XCTAssertEqual(provider.appLaunchProfilingSampled, true)
        XCTAssertEqual(provider.continuousProfilingSampled, false)
        XCTAssertEqual(server.waitAndReturnRequests(count: 1).count, 1)
    }

    func testChecksQuotaForAppLaunchWhenContinuousProfilingIsDisabled() {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: false, reason: .quotaExceeded)
            )
        )
        let (checker, provider, receiver) = quotaReceiver(
            for: server,
            continuousSampleRate: 0,
            appLaunchSampleRate: 100
        )
        let rejected = expectation(description: "app-launch quota rejected")
        checker.onQuotaResultUpdate = { result in
            if result?.decision == .quotaKO {
                rejected.fulfill()
            }
        }
        let context = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 100)]
        )

        // When
        _ = receiver.receive(message: .context(context), from: PassthroughCoreMock())

        // Then
        XCTAssertEqual(provider.continuousProfilingSampled, false)
        XCTAssertEqual(server.waitAndReturnRequests(count: 1).count, 1)
        wait(for: [rejected], timeout: 1.0)
        XCTAssertEqual(checker.quotaResult, .init(decision: .quotaKO, reason: .quotaExceeded))
    }

    func testDoesNotCheckQuotaForAppLaunchWhenRUMSessionSamplesOut() {
        // Given
        let server = quotaServer()
        let (_, provider, receiver) = quotaReceiver(
            for: server,
            continuousSampleRate: 100,
            appLaunchSampleRate: 100
        )
        let context = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 0)]
        )

        // When
        _ = receiver.receive(message: .context(context), from: PassthroughCoreMock())

        // Then
        XCTAssertEqual(provider.continuousProfilingSampled, false)
        XCTAssertEqual(server.waitAndReturnRequests(count: 0, timeout: 0.1).count, 0)
    }

    func testZeroContinuousRateDoesNotCheckQuotaEvenForOperationStart() {
        // Given
        let server = quotaServer()
        let (_, _, receiver) = quotaReceiver(for: server, continuousSampleRate: 0)
        let core = PassthroughCoreMock()
        let context = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 100)]
        )
        let start = OperationMessage(attributes: [:], operation: .mockWith(stepType: .start))

        // When
        _ = receiver.receive(message: .context(context), from: core)
        _ = receiver.receive(message: .payload(start), from: core)
        _ = receiver.receive(message: .payload(start), from: core)
        _ = receiver.receive(message: .context(context), from: core)

        // Then
        XCTAssertEqual(server.waitAndReturnRequests(count: 0, timeout: 0.1).count, 0)
    }

    func testChecksQuotaWhenContinuousSamplingDecisionArrivesAfterInitialContext() {
        // Given
        let server = quotaServer()
        let (_, provider, receiver) = quotaReceiver(for: server, continuousSampleRate: 100)
        let core = PassthroughCoreMock()
        let initialContext = DatadogContext.mockWith(trackingConsent: .granted, additionalContext: [])
        let rumContext = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: 100)]
        )

        // When
        _ = receiver.receive(message: .context(initialContext), from: core)

        // Then
        XCTAssertNil(provider.continuousProfilingSampled)

        // When
        _ = receiver.receive(message: .context(rumContext), from: core)

        // Then
        XCTAssertEqual(provider.continuousProfilingSampled, true)
        XCTAssertEqual(server.waitAndReturnRequests(count: 1).count, 1)
    }

    func testNewSampledInSessionChecksQuotaOnceAfterSampledOutSession() {
        // Given
        let server = quotaServer()
        let (_, _, receiver) = quotaReceiver(for: server, continuousSampleRate: 100)
        let core = PassthroughCoreMock()
        let firstSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let sampledOutSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let nextSessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let firstContext = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionID: firstSessionID, sessionSampleRate: 100)]
        )
        let sampledOutContext = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionID: sampledOutSessionID, sessionSampleRate: 0)]
        )
        let nextContext = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionID: nextSessionID, sessionSampleRate: 100)]
        )

        // When
        _ = receiver.receive(message: .context(firstContext), from: core)
        _ = receiver.receive(message: .context(sampledOutContext), from: core)
        _ = receiver.receive(message: .context(nextContext), from: core)
        _ = receiver.receive(message: .context(nextContext), from: core)

        // Then
        XCTAssertEqual(server.waitAndReturnRequests(count: 2).count, 2)
    }

    func testMapResponse_returnsQuotaKO_forQuotaExceeded() {
        // Given
        let response = quotaResponse(admitted: false, reason: .quotaExceeded)

        // When
        let result = ProfilingQuotaChecker.mapResponse(
            data: response,
            response: HTTPURLResponse.mockResponseWith(statusCode: 200),
            error: nil
        )

        // Then
        XCTAssertEqual(result, .init(decision: .quotaKO, reason: .quotaExceeded))
    }

    func testMapResponse_returnsQuotaOK_forBackendUnavailable() {
        // Given
        let response = quotaResponse(admitted: false, reason: .backendUnavailable)

        // When
        let result = ProfilingQuotaChecker.mapResponse(
            data: response,
            response: HTTPURLResponse.mockResponseWith(statusCode: 200),
            error: nil
        )

        // Then
        XCTAssertEqual(result, .init(decision: .quotaOK, reason: .backendUnavailable))
    }

    func testMapResponse_normalizesUnknownReason_toUndefined() {
        // Given
        let response = quotaResponse(admitted: true, rawReason: .mockAny())

        // When
        let result = ProfilingQuotaChecker.mapResponse(
            data: response,
            response: HTTPURLResponse.mockResponseWith(statusCode: 200),
            error: nil
        )

        // Then
        XCTAssertEqual(result, .init(decision: .quotaOK, reason: .undefined))
    }

    func testMapResponse_returnsQuotaKO_whenNotAdmittedWithUnknownReason() {
        // Given
        let response = quotaResponse(admitted: false, rawReason: .mockAny())

        // When
        let result = ProfilingQuotaChecker.mapResponse(
            data: response,
            response: HTTPURLResponse.mockResponseWith(statusCode: 200),
            error: nil
        )

        // Then
        XCTAssertEqual(result, .init(decision: .quotaKO, reason: .undefined))
    }

    func testMapResponse_returnsTimeout_whenRequestTimesOut() {
        // When
        let result = ProfilingQuotaChecker.mapResponse(
            data: nil,
            response: nil,
            error: URLError(.timedOut)
        )

        // Then
        XCTAssertEqual(result, .init(decision: .quotaOK, reason: .timeout))
    }

    func testMapResponse_returnsAPIError_whenPayloadIsInvalid() {
        // When
        let result = ProfilingQuotaChecker.mapResponse(
            data: Data("invalid".utf8),
            response: HTTPURLResponse.mockResponseWith(statusCode: 200),
            error: nil
        )

        // Then
        XCTAssertEqual(result, .init(decision: .quotaOK, reason: .apiError))
    }

    func testDeduplicatesRepeatedContexts_forSameSession() {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = quotaChecker(for: server)
        let context = DatadogContext.mockWith(
            site: .us1,
            clientToken: "test-client-token",
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )

        // When
        _ = checker.receive(message: FeatureMessage.context(context), from: PassthroughCoreMock())
        _ = checker.receive(message: FeatureMessage.context(context), from: PassthroughCoreMock())

        // Then
        XCTAssertEqual(server.waitAndReturnRequests(count: 1).count, 1)
    }

    func testStartsNewRequest_whenSessionChanges() {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = quotaChecker(for: server)
        let firstContext = DatadogContext.mockWith(
            site: .us1,
            clientToken: "test-client-token",
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionID: .mockAny(), sessionSampleRate: .maxSampleRate)]
        )
        let secondContext = DatadogContext.mockWith(
            site: .us1,
            clientToken: "test-client-token",
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionID: .mockAny(), sessionSampleRate: .maxSampleRate)]
        )

        // When
        _ = checker.receive(message: FeatureMessage.context(firstContext), from: PassthroughCoreMock())
        _ = checker.receive(message: FeatureMessage.context(secondContext), from: PassthroughCoreMock())

        // Then
        XCTAssertEqual(server.waitAndReturnRequests(count: 2).count, 2)
    }

    func testSessionChange_resetsQuotaAndAllowsReentrantContextDelivery() throws {
        let session = ControlledQuotaSession()
        let provider = ProfilingSamplerProvider(continuousSampleRate: 100)
        provider.updateWith(deterministicSampler: DeterministicSampler(seed: 1, samplingRate: 100))
        let checker = ProfilingQuotaChecker(profilingSamplerProvider: provider, urlSession: session)
        let core = PassthroughCoreMock()
        defer {
            checker.onQuotaResultUpdate = nil
            session.invalidateAndCancel()
        }
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        let first = quotaContext(sessionID: firstSessionID)
        let second = quotaContext(sessionID: secondSessionID)
        let currentContext = ReadWriteLock(wrappedValue: first)
        let updates = ReadWriteLock<[ProfilingQuotaResult?]>(wrappedValue: [])
        let snapshots = ReadWriteLock<[ProfilingQuotaResult?]>(wrappedValue: [])
        checker.onQuotaResultUpdate = { result in
            updates.mutate { $0.append(result) }
            snapshots.mutate { $0.append(checker.quotaResult) }
            _ = checker.receive(message: .context(currentContext.wrappedValue), from: core)
        }

        _ = checker.receive(message: .context(first), from: core)
        XCTAssertEqual(session.quotaTasks.count, 1)
        let firstTask = try XCTUnwrap(session.quotaTasks.first)
        XCTAssertTrue(firstTask.wasResumed)
        XCTAssertEqual(firstTask.sessionID, firstSessionID.uuidString.lowercased())
        firstTask.complete(data: quotaResponse(admitted: false, reason: .quotaExceeded))

        let rejected = ProfilingQuotaResult(decision: .quotaKO, reason: .quotaExceeded)
        XCTAssertEqual(checker.quotaResult, rejected)
        XCTAssertEqual(updates.wrappedValue, [rejected])
        XCTAssertEqual(snapshots.wrappedValue, [rejected])
        XCTAssertTrue(checker.isRejectedByQuota)
        attachQuotaBoundary(
            "rejected-first-session",
            checker: checker,
            session: session,
            updates: updates.wrappedValue,
            expectedSessionIDs: [firstSessionID, secondSessionID]
        )

        currentContext.mutate { $0 = second }
        _ = checker.receive(message: .context(second), from: core)
        XCTAssertNil(checker.quotaResult)
        XCTAssertFalse(checker.isRejectedByQuota)
        XCTAssertEqual(updates.wrappedValue, [rejected, nil])
        XCTAssertEqual(snapshots.wrappedValue, [rejected, nil])
        XCTAssertEqual(session.quotaTasks.count, 2)
        attachQuotaBoundary(
            "reset-pending-second-session",
            checker: checker,
            session: session,
            updates: updates.wrappedValue,
            expectedSessionIDs: [firstSessionID, secondSessionID]
        )

        let secondTask = try XCTUnwrap(session.quotaTasks.last)
        XCTAssertTrue(secondTask.wasResumed)
        XCTAssertEqual(session.quotaTasks.map(\.sessionID), [firstSessionID, secondSessionID].map { $0.uuidString.lowercased() })
        secondTask.complete(data: quotaResponse(admitted: true, reason: .quotaOk))
        let admitted = ProfilingQuotaResult(decision: .quotaOK, reason: .quotaOk)
        XCTAssertEqual(checker.quotaResult, admitted)
        XCTAssertEqual(updates.wrappedValue, [rejected, nil, admitted])
        XCTAssertEqual(snapshots.wrappedValue, [rejected, nil, admitted])
        XCTAssertEqual(session.quotaTasks.count, 2)
        XCTAssertEqual(session.quotaTasks.map(\.completionCount), [1, 1])
        attachQuotaBoundary(
            "admitted-second-session",
            checker: checker,
            session: session,
            updates: updates.wrappedValue,
            expectedSessionIDs: [firstSessionID, secondSessionID]
        )
    }

    func testLateQuotaResponse_doesNotOverwriteNewSessionOrNotifyListener() throws {
        for oldResponseFirst in [true, false] {
            let session = ControlledQuotaSession()
            let provider = ProfilingSamplerProvider(continuousSampleRate: 100)
            provider.updateWith(deterministicSampler: DeterministicSampler(seed: 1, samplingRate: 100))
            let checker = ProfilingQuotaChecker(profilingSamplerProvider: provider, urlSession: session)
            let core = PassthroughCoreMock()
            defer {
                checker.onQuotaResultUpdate = nil
                session.invalidateAndCancel()
            }
            let updates = ReadWriteLock<[ProfilingQuotaResult?]>(wrappedValue: [])
            checker.onQuotaResultUpdate = { result in updates.mutate { $0.append(result) } }

            let firstSessionID = UUID()
            let secondSessionID = UUID()
            _ = checker.receive(message: .context(quotaContext(sessionID: firstSessionID)), from: core)
            _ = checker.receive(message: .context(quotaContext(sessionID: secondSessionID)), from: core)
            XCTAssertEqual(session.quotaTasks.count, 2)
            XCTAssertEqual(updates.wrappedValue, [nil])
            let firstTask = try XCTUnwrap(session.quotaTasks.first)
            let secondTask = try XCTUnwrap(session.quotaTasks.last)
            XCTAssertTrue(firstTask.wasResumed)
            XCTAssertTrue(secondTask.wasResumed)
            XCTAssertEqual(session.quotaTasks.map(\.sessionID), [firstSessionID, secondSessionID].map { $0.uuidString.lowercased() })

            if oldResponseFirst {
                firstTask.complete(data: quotaResponse(admitted: true, reason: .quotaOk))
                XCTAssertNil(checker.quotaResult)
                XCTAssertEqual(updates.wrappedValue, [nil])
            }
            secondTask.complete(data: quotaResponse(admitted: false, reason: .quotaExceeded))
            if !oldResponseFirst {
                firstTask.complete(data: quotaResponse(admitted: true, reason: .quotaOk))
            }

            let rejected = ProfilingQuotaResult(decision: .quotaKO, reason: .quotaExceeded)
            XCTAssertEqual(checker.quotaResult, rejected)
            XCTAssertTrue(checker.isRejectedByQuota)
            XCTAssertEqual(updates.wrappedValue, [nil, rejected])
            XCTAssertEqual(session.quotaTasks.map(\.completionCount), [1, 1])
            attachQuotaBoundary(
                oldResponseFirst ? "stale-before-current" : "stale-after-current",
                checker: checker,
                session: session,
                updates: updates.wrappedValue,
                expectedSessionIDs: [firstSessionID, secondSessionID]
            )
        }
    }

    func testNotifiesQuotaResultUpdate() {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = quotaChecker(for: server)
        let core = PassthroughCoreMock()
        let context = DatadogContext.mockWith(
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )
        let expectation = expectation(description: "quota update")
        checker.onQuotaResultUpdate = { result in
            guard result?.reason == .quotaOk else {
                return
            }

            expectation.fulfill()
        }

        // When
        _ = checker.receive(message: FeatureMessage.context(context), from: core)
        _ = server.waitAndReturnRequests(count: 1)

        // Then
        wait(for: [expectation], timeout: 1.0)
    }
}

private extension ProfilingQuotaCheckerTests {
    func attachQuotaBoundary(
        _ boundary: String,
        checker: ProfilingQuotaChecker,
        session: ControlledQuotaSession,
        updates: [ProfilingQuotaResult?],
        expectedSessionIDs: [UUID]
    ) {
        func encode(_ result: ProfilingQuotaResult?) -> Any {
            guard let result else {
                return NSNull()
            }
            return ["decision": String(describing: result.decision), "reason": result.reason.rawValue]
        }
        var images: [String] = []
        for index in 0..<_dyld_image_count() {
            if let image = _dyld_get_image_name(index) { images.append(String(cString: image)) }
        }
        let inventory: [String: Any] = [
            "schema_version": 1, "family": "quota-session-semantics",
            "boundary": boundary, "pid": ProcessInfo.processInfo.processIdentifier, "loaded_images": images,
            "result": encode(checker.quotaResult), "is_rejected": checker.isRejectedByQuota,
            "updates": updates.map(encode),
            "expected_session_ids": expectedSessionIDs.map { $0.uuidString.lowercased() },
            "tasks": session.quotaTasks.map {
                [
                    "session_id": $0.sessionID ?? "",
                    "resumed": $0.wasResumed,
                    "completions": $0.completionCount
                ] as [String: Any]
            }
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: inventory, options: [.sortedKeys]) else {
            return XCTFail("Failed to encode the quota boundary inventory.")
        }
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "quota-session-" + boundary
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func quotaContext(sessionID: UUID) -> DatadogContext {
        DatadogContext.mockWith(
            site: .us1,
            clientToken: "test-client-token",
            trackingConsent: .granted,
            additionalContext: [RUMCoreContext.mockWith(sessionID: sessionID, sessionSampleRate: .maxSampleRate)]
        )
    }

    func quotaServer() -> ServerMock {
        ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
    }

    func quotaChecker(for server: ServerMock) -> ProfilingQuotaChecker {
        let provider = ProfilingSamplerProvider(continuousSampleRate: 100)
        provider.updateWith(deterministicSampler: DeterministicSampler(seed: 1, samplingRate: 100))
        return ProfilingQuotaChecker(
            profilingSamplerProvider: provider,
            urlSession: server.getInterceptedURLSession()
        )
    }

    func quotaReceiver(
        for server: ServerMock,
        continuousSampleRate: SampleRate,
        appLaunchSampleRate: SampleRate = 0
    ) -> (ProfilingQuotaChecker, ProfilingSamplerProvider, CombinedFeatureMessageReceiver) {
        let provider = ProfilingSamplerProvider(
            continuousSampleRate: continuousSampleRate,
            appLaunchSampleRate: appLaunchSampleRate
        )
        let checker = ProfilingQuotaChecker(
            profilingSamplerProvider: provider,
            urlSession: server.getInterceptedURLSession()
        )
        let receiver = CombinedFeatureMessageReceiver([
            ProfilingContextMessageReceiver(profilingSamplerProvider: provider),
            checker
        ])
        return (checker, provider, receiver)
    }

    private func quotaResponse(admitted: Bool, reason: DDProfiling.QuotaReason) -> Data {
        quotaResponse(admitted: admitted, rawReason: reason.rawValue)
    }

    private func quotaResponse(admitted: Bool, rawReason: String) -> Data {
        Data(
            """
            {"data":{"id":"quota","type":"profiling-quota","attributes":{"admitted":\(admitted),"reason":"\(rawReason)"}}}
            """.utf8
        )
    }
}

private final class ControlledQuotaSession: URLSession, @unchecked Sendable {
    private let recordedTasks = ReadWriteLock<[ControlledQuotaTask]>(wrappedValue: [])
    var quotaTasks: [ControlledQuotaTask] { recordedTasks.wrappedValue }

    override init() {
        super.init()
    }

    override func invalidateAndCancel() {
        // This transport owns only controlled tasks and no Foundation session resources.
    }

    override func dataTask(
        with request: URLRequest,
        completionHandler: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void
    ) -> URLSessionDataTask {
        let task = ControlledQuotaTask(request: request, completion: completionHandler)
        recordedTasks.mutate { $0.append(task) }
        return task
    }
}

private final class ControlledQuotaTask: URLSessionDataTask, @unchecked Sendable {
    private struct State {
        var wasResumed = false
        var completionCount = 0
    }
    private let recordedState = ReadWriteLock(wrappedValue: State())
    private let request: URLRequest
    private let completion: @Sendable (Data?, URLResponse?, Error?) -> Void
    override var originalRequest: URLRequest? { request }
    var sessionID: String? {
        request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first(where: { $0.name == "session_id" })?.value
    }
    var wasResumed: Bool { recordedState.wrappedValue.wasResumed }
    var completionCount: Int { recordedState.wrappedValue.completionCount }

    init(request: URLRequest, completion: @escaping @Sendable (Data?, URLResponse?, Error?) -> Void) {
        self.request = request
        self.completion = completion
        super.init()
    }

    override func resume() {
        recordedState.mutate { $0.wasResumed = true }
    }

    func complete(data: Data) {
        recordedState.mutate { $0.completionCount += 1 }
        completion(data, HTTPURLResponse.mockResponseWith(statusCode: 200), nil)
    }
}

final class ProfilingQuotaCheckerMock: ProfilingQuotaChecking, @unchecked Sendable {
    private(set) var receivedContexts: [DatadogContext] = []
    var quotaResult: ProfilingQuotaResult?
    var onQuotaResultUpdate: ProfilingQuotaResultListener?
    var receiveHandler: ((DatadogContext) -> ProfilingQuotaResult?)?
    private var currentSessionID: String?

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message,
              let rumContext = context.additionalContext(ofType: RUMCoreContext.self) else {
            return false
        }

        receivedContexts.append(context)

        if currentSessionID != rumContext.sessionID {
            currentSessionID = rumContext.sessionID
            quotaResult = nil
            onQuotaResultUpdate?(nil)
        }

        if let result = receiveHandler?(context) {
            quotaResult = result
            onQuotaResultUpdate?(result)
        }

        return false
    }
}

#endif
