/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if !os(watchOS)

import XCTest
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
