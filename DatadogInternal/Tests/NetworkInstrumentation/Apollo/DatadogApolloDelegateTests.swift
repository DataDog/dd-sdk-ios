/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if Apollo
import XCTest
@testable import DatadogInternal

final class DatadogApolloDelegateTests: XCTestCase {
    func testCompletionReturnsAccumulatedDataAndResponse() async throws {
        let delegate = DatadogApolloDelegate()
        let url = URL(string: "https://example.com/graphql")!
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let task = MockURLSessionDataTask(url: url, response: response)

        let (data, receivedResponse) = try await withCheckedThrowingContinuation { continuation in
            delegate.registerContinuation(for: task, continuation: continuation)
            delegate.urlSession(.shared, dataTask: task, didReceive: Data("Hello".utf8))
            delegate.urlSession(.shared, dataTask: task, didReceive: Data(" World".utf8))
            delegate.urlSession(.shared, task: task, didCompleteWithError: nil)
            // A repeated completion must not resume the continuation a second time.
            delegate.urlSession(.shared, task: task, didCompleteWithError: nil)
        }

        XCTAssertEqual(data, Data("Hello World".utf8))
        XCTAssertTrue(receivedResponse === response)
    }

    func testCompletionPropagatesError() async throws {
        let delegate = DatadogApolloDelegate()
        let task = MockURLSessionDataTask(url: URL(string: "https://example.com/graphql")!, response: nil)

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                delegate.registerContinuation(for: task, continuation: continuation)
                delegate.urlSession(.shared, task: task, didCompleteWithError: URLError(.timedOut))
            }
            XCTFail("Expected the task error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }

    func testCompletionWithoutResponseFails() async throws {
        let delegate = DatadogApolloDelegate()
        let task = MockURLSessionDataTask(url: URL(string: "https://example.com/graphql")!, response: nil)

        do {
            _ = try await withCheckedThrowingContinuation { continuation in
                delegate.registerContinuation(for: task, continuation: continuation)
                delegate.urlSession(.shared, task: task, didCompleteWithError: nil)
            }
            XCTFail("Expected a missing response error")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .badServerResponse)
        }
    }
}
#endif
