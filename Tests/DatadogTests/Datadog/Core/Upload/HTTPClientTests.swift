/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class HTTPClientTests: XCTestCase {
    func testWhenRequestIsDelivered_itReturnsHTTPResponse() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let expectation = self.expectation(description: "receive response")
        let client = HTTPClient(session: .serverMockURLSession)

        client.send(request: .mockAny()) { result in
            switch result {
            case .success(let httpResponse):
                XCTAssertEqual(httpResponse.statusCode, 200)
                expectation.fulfill()
            case .failure:
                break
            }
        }

        waitForExpectations(timeout: 1, handler: nil)
        server.waitFor(requestsCompletion: 1)
    }

    func testWhenRequestIsNotDelivered_itReturnsHTTPRequestDeliveryError() {
        let mockError = NSError(domain: "network", code: 999, userInfo: [NSLocalizedDescriptionKey: "no internet connection"])
        let server = ServerMock(delivery: .failure(error: mockError))
        let expectation = self.expectation(description: "receive response")
        let client = HTTPClient(session: .serverMockURLSession)

        client.send(request: .mockAny()) { result in
            switch result {
            case .success:
                break
            case .failure(let error):
                XCTAssertEqual((error as NSError).localizedDescription, "no internet connection")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 1, handler: nil)
        server.waitFor(requestsCompletion: 1)
    }
}
