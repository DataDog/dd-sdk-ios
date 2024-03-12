/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

@testable import DatadogInternal

class URLSessionSwizzlerTests: XCTestCase {
    func testSwizzling_dataTaskWithCompletion() throws {
        let didReceive = expectation(description: "didReceive")
        didReceive.expectedFulfillmentCount = 2

        let didInterceptCompletion = expectation(description: "interceptCompletion")
        didInterceptCompletion.expectedFulfillmentCount = 2

        let swizzler = URLSessionSwizzler()

        try swizzler.swizzle(
            interceptCompletionHandler: { _, _, _ in
                didInterceptCompletion.fulfill()
            }, didReceive: { _, _ in
                didReceive.fulfill()
            }
        )

        let session = URLSession(configuration: .default)
        let url = URL(string: "https://www.datadoghq.com/")!
        session.dataTask(with: url) { _, _, _ in }.resume() // intercepted
        session.dataTask(with: URLRequest(url: url)) { _, _, _ in }.resume() // intercepted

        swizzler.unswizzle()
        session.dataTask(with: url) { _, _, _ in }.resume() // not intercepted
        session.dataTask(with: URLRequest(url: url)) { _, _, _ in }.resume() // not intercepted

        wait(for: [didReceive, didInterceptCompletion], timeout: 5)
    }
}
