/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogCore

class HTTPClientTests: XCTestCase {
    func testWhenRequestIsDelivered_itReturnsHTTPResponse() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let expectation = self.expectation(description: "receive response")
        let client = HTTPClient(session: server.getInterceptedURLSession())

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
        let client = HTTPClient(session: server.getInterceptedURLSession())

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

    func testWhenProxyConfigurationIsSet_itUsesProxyConfiguration() {
        let proxyConfiguration: [AnyHashable: Any] = [
            kCFNetworkProxiesHTTPEnable: true,
            kCFNetworkProxiesHTTPPort: 123,
            kCFNetworkProxiesHTTPProxy: "www.example.com",
            kCFProxyUsernameKey: "proxyuser",
            kCFProxyPasswordKey: "proxypass",
        ]

        let client = HTTPClient(proxyConfiguration: proxyConfiguration)

        let actualProxy: [AnyHashable: Any] = client.session.configuration.connectionProxyDictionary!
        XCTAssertEqual(actualProxy[kCFNetworkProxiesHTTPEnable] as? Bool, true)
        XCTAssertEqual(actualProxy[kCFNetworkProxiesHTTPPort] as? Int, 123)
        XCTAssertEqual(actualProxy[kCFNetworkProxiesHTTPProxy] as? String, "www.example.com")
        XCTAssertEqual(actualProxy[kCFProxyUsernameKey] as? String, "proxyuser")
        XCTAssertEqual(actualProxy[kCFProxyPasswordKey] as? String, "proxypass")
        XCTAssertEqual(
            client.session.configuration.httpAdditionalHeaders?["Proxy-Authorization"] as? String,
            "Basic cHJveHl1c2VyOnByb3h5cGFzcw==" // Base64.encode(proxyuser:proxypass)
        )
    }
}
