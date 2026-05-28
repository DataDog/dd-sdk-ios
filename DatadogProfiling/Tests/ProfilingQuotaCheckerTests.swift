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
    func testReceive_buildsQuotaURLAndHeaders() throws {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = ProfilingQuotaChecker(
            urlSession: server.getInterceptedURLSession()
        )
        let sessionID = UUID(uuidString: "abcdef01-2345-6789-abcd-ef0123456789")!
        let context = DatadogContext.mockWith(
            site: .us1,
            clientToken: "test-client-token",
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

    func testReceive_doesNothingWhenContextHasNoRUMSession() {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = ProfilingQuotaChecker(
            urlSession: server.getInterceptedURLSession()
        )

        // When
        _ = checker.receive(
            message: FeatureMessage.context(DatadogContext.mockWith(additionalContext: [])),
            from: PassthroughCoreMock()
        )

        // Then
        XCTAssertEqual(server.waitAndReturnRequests(count: 0, timeout: 0.1).count, 0)
        XCTAssertNil(checker.currentQuotaCheckResult)
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

    func testMapResponse_normalizesBackendClientNotInitialized_toBackendUnavailable() {
        // Given
        let response = quotaResponse(
            admitted: false,
            rawReason: "backend_client_not_initialized"
        )

        // When
        let result = ProfilingQuotaChecker.mapResponse(
            data: response,
            response: HTTPURLResponse.mockResponseWith(statusCode: 200),
            error: nil
        )

        // Then
        XCTAssertEqual(result, .init(decision: .quotaOK, reason: .backendUnavailable))
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

    func testReceive_deduplicatesRepeatedContexts_forSameSession() {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = ProfilingQuotaChecker(
            urlSession: server.getInterceptedURLSession()
        )
        let context = DatadogContext.mockWith(
            site: .us1,
            clientToken: "test-client-token",
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )

        // When
        _ = checker.receive(message: FeatureMessage.context(context), from: PassthroughCoreMock())
        _ = checker.receive(message: FeatureMessage.context(context), from: PassthroughCoreMock())

        // Then
        XCTAssertEqual(server.waitAndReturnRequests(count: 1).count, 1)
    }

    func testReceive_startsNewRequest_whenSessionChanges() {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = ProfilingQuotaChecker(
            urlSession: server.getInterceptedURLSession()
        )
        let firstContext = DatadogContext.mockWith(
            site: .us1,
            clientToken: "test-client-token",
            additionalContext: [RUMCoreContext.mockWith(sessionID: UUID(uuidString: "abcdef01-2345-6789-abcd-ef0123456789")!, sessionSampleRate: .maxSampleRate)]
        )
        let secondContext = DatadogContext.mockWith(
            site: .us1,
            clientToken: "test-client-token",
            additionalContext: [RUMCoreContext.mockWith(sessionID: UUID(uuidString: "fedcba98-7654-3210-fedc-ba9876543210")!, sessionSampleRate: .maxSampleRate)]
        )

        // When
        _ = checker.receive(message: FeatureMessage.context(firstContext), from: PassthroughCoreMock())
        _ = checker.receive(message: FeatureMessage.context(secondContext), from: PassthroughCoreMock())

        // Then
        XCTAssertEqual(server.waitAndReturnRequests(count: 2).count, 2)
    }

    func testReceive_updatesProfilingContextWithQuotaReason() throws {
        // Given
        let server = ServerMock(
            delivery: .success(
                response: .mockResponseWith(statusCode: 200),
                data: quotaResponse(admitted: true, reason: .quotaOk)
            )
        )
        let checker = ProfilingQuotaChecker(
            urlSession: server.getInterceptedURLSession()
        )
        let core = PassthroughCoreMock()
        let context = DatadogContext.mockWith(
            additionalContext: [RUMCoreContext.mockWith(sessionSampleRate: .maxSampleRate)]
        )

        // When
        _ = checker.receive(message: FeatureMessage.context(context), from: core)
        _ = server.waitAndReturnRequests(count: 1)
        Thread.sleep(forTimeInterval: 0.05)

        // Then
        let profilingContext = try XCTUnwrap(core.context.additionalContext(ofType: ProfilingContext.self))
        XCTAssertEqual(profilingContext.quotaReason, .quotaOk)
    }

    private func quotaResponse(admitted: Bool, reason: ProfilingContext.QuotaReason) -> Data {
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
    var currentQuotaCheckResult: ProfilingQuotaCheckResult?
    var receiveHandler: ((DatadogContext) -> ProfilingQuotaCheckResult?)?

    func receive(message: FeatureMessage, from core: DatadogCoreProtocol) -> Bool {
        guard case let .context(context) = message,
              context.additionalContext(ofType: RUMCoreContext.self) != nil else {
            return false
        }

        receivedContexts.append(context)

        if let result = receiveHandler?(context) {
            currentQuotaCheckResult = result
            core.set(
                context: ProfilingContext(
                    status: .current,
                    quotaReason: result.reason
                )
            )
        }

        return false
    }
}

#endif
