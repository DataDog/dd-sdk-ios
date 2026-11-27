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

final class PrecomputedConfigurationFetcherTests: XCTestCase {
    private let featureScope = FeatureScopeMock()
    private let now = Date(timeIntervalSince1970: 1_700_000_000.250)

    private func makeFetcher(
        mode: FlagsClient.ExperimentationOptOutMode = .disabled,
        body: Data = .mockAnyFlagAssignmentsResponse(),
        headers: [String: String]? = nil,
        onRequest: @escaping (URLRequest) -> Void = { _ in }
    ) -> PrecomputedConfigurationFetcher {
        let fetcher = FlagAssignmentsFetcher(
            customEndpoint: nil,
            customHeaders: nil,
            flagSelection: nil,
            featureScope: featureScope,
            fetch: { request, completion in
                onRequest(request)
                // swiftlint:disable:next force_unwrapping
                let response = HTTPURLResponse(url: .mockAny(), statusCode: 200, httpVersion: nil, headerFields: headers)!
                completion(.success((body, response)))
            }
        )
        return PrecomputedConfigurationFetcher(
            fetcher: fetcher,
            experimentationOptOutMode: mode,
            dateProvider: DateProviderMock(now: now)
        )
    }

    private func fetch(
        _ fetcher: PrecomputedConfigurationFetcher,
        context: FlagsEvaluationContext = .mockAny()
    ) -> Result<FetchedPrecomputedConfiguration, FlagsError>? {
        let completed = expectation(description: "completed")
        var captured: Result<FetchedPrecomputedConfiguration, FlagsError>?
        fetcher.fetch(for: context) { result in
            captured = result
            completed.fulfill()
        }
        wait(for: [completed], timeout: 1)
        return captured
    }

    func testFetchReturnsDetachedConfiguration() throws {
        // Given
        let body = Data.mockAnyFlagAssignmentsResponse()
        let context = FlagsEvaluationContext(targetingKey: "user-1", attributes: ["plan": .string("premium")])
        let fetcher = makeFetcher(body: body, headers: ["ETag": "\"abc123\""])

        // When
        let configuration = try XCTUnwrap(fetch(fetcher, context: context)?.get())

        // Then
        XCTAssertEqual(configuration.response, String(decoding: body, as: UTF8.self))
        XCTAssertEqual(configuration.context, context)
        XCTAssertEqual(configuration.fetchedAt, 1_700_000_000_250, accuracy: 0.5)
        XCTAssertEqual(configuration.etag, "\"abc123\"")
        XCTAssertEqual(configuration.assignments.flags, FlagAssignmentsResponse.mockAny().flags)
    }

    func testFetchKeepsNilEtagWhenHeaderIsAbsentOrEmpty() throws {
        for headers in [nil, ["ETag": ""]] as [[String: String]?] {
            // When
            let configuration = try XCTUnwrap(fetch(makeFetcher(headers: headers))?.get())

            // Then
            XCTAssertNil(configuration.etag, "headers: \(String(describing: headers))")
        }
    }

    func testFetchSendsTheAssignmentTokenButKeepsItOutOfTheConfiguration() throws {
        // Given
        var capturedRequest: URLRequest?
        let context = FlagsEvaluationContext(
            targetingKey: "user-1",
            attributes: ["plan": .string("premium"), "dd_assignment_token": .string("header.payload.signature")]
        )
        let fetcher = makeFetcher(onRequest: { capturedRequest = $0 })

        // When
        let configuration = try XCTUnwrap(fetch(fetcher, context: context)?.get())

        // Then
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "DD-Assignment-Token"), "header.payload.signature")
        XCTAssertNil(configuration.context.attributes["dd_assignment_token"])
        XCTAssertEqual(configuration.context.attributes["plan"], .string("premium"))
    }

    func testFetchRejectsMalformedOptOutWithoutARequest() {
        // Given
        var requestCount = 0
        let fetcher = makeFetcher(mode: .immediate, onRequest: { _ in requestCount += 1 })
        let context = FlagsEvaluationContext(
            targetingKey: "user-1",
            attributes: ["dd_experimentation_opt_out_at": .int(1)]
        )

        // When
        let result = fetch(fetcher, context: context)

        // Then
        guard case .failure(.invalidContext) = result else {
            return XCTFail("Expected invalidContext, got \(String(describing: result))")
        }
        XCTAssertEqual(requestCount, 0)
    }

    func testFetchSendsInitializationThenContextChangeDiagnostics() throws {
        // Given
        var bodies: [[String: Any]] = []
        let fetcher = makeFetcher(onRequest: { request in
            if let body = request.httpBody,
               let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
                bodies.append(json)
            }
        })

        // When
        _ = fetch(fetcher)
        _ = fetch(fetcher)

        // Then
        XCTAssertEqual(bodies.count, 2)
        let diagnostics = bodies.map { $0["diagnostics"] as? [String: Any] }
        let fetches = diagnostics.map { $0?["fetch"] as? [String: Any] }
        XCTAssertEqual(fetches[0]?["sequence"] as? Int, 1)
        XCTAssertEqual(fetches[0]?["trigger"] as? String, "initialization")
        XCTAssertEqual(fetches[1]?["sequence"] as? Int, 2)
        XCTAssertEqual(fetches[1]?["trigger"] as? String, "context_change")
        let instanceIDs = diagnostics.map { ($0?["sdk"] as? [String: Any])?["instance_id"] as? String }
        XCTAssertNotNil(instanceIDs[0])
        XCTAssertEqual(instanceIDs[0], instanceIDs[1])
    }

    func testFetchPropagatesNetworkErrors() {
        // Given
        let fetcher = PrecomputedConfigurationFetcher(
            fetcher: FlagAssignmentsFetcher(
                customEndpoint: nil,
                customHeaders: nil,
                flagSelection: nil,
                featureScope: featureScope,
                fetch: { _, completion in completion(.failure(URLError(.notConnectedToInternet))) }
            ),
            dateProvider: DateProviderMock(now: now)
        )

        // When
        let result = fetch(fetcher)

        // Then
        guard case .failure(.networkError) = result else {
            return XCTFail("Expected networkError, got \(String(describing: result))")
        }
    }

    func testFetchRejectsAnUndecodableBody() {
        // When
        let result = fetch(makeFetcher(body: Data("not json".utf8)))

        // Then
        guard case .failure(.invalidResponse) = result else {
            return XCTFail("Expected invalidResponse, got \(String(describing: result))")
        }
    }
}
