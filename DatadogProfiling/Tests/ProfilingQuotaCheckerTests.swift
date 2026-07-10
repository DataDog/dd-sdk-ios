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
        let checker = ProfilingQuotaChecker(urlSession: server.getInterceptedURLSession())
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
        let checker = ProfilingQuotaChecker(urlSession: server.getInterceptedURLSession())

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
        let checker = ProfilingQuotaChecker(urlSession: server.getInterceptedURLSession())

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
        let checker = ProfilingQuotaChecker(urlSession: server.getInterceptedURLSession())
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
        let checker = ProfilingQuotaChecker(urlSession: server.getInterceptedURLSession())
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
        let checker = ProfilingQuotaChecker(urlSession: server.getInterceptedURLSession())
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
        let checker = ProfilingQuotaChecker(urlSession: server.getInterceptedURLSession())
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
        let checker = ProfilingQuotaChecker(urlSession: server.getInterceptedURLSession())
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
        waitForExpectations(timeout: 1.0)
    }
}

private extension ProfilingQuotaCheckerTests {
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

final class ProfilingQuotaCheckerMock: ProfilingQuotaChecking {
    private(set) var receivedContexts: [DatadogContext] = []
    var quotaResult: ProfilingQuotaResult?
    var onQuotaResultUpdate: ((ProfilingQuotaResult?) -> Void)?
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
