/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal

internal final class _DatadogURLSessionDelegate: DatadogURLSessionDelegate {
    let property: String
    override init() {
        property = "someProp"
        super.init()
    }
    override func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        super.urlSession(session, task: task, didCompleteWithError: error)
    }
}

class DDURLSessionDelegateAsSuperclassTests: XCTestCase {
    func testSubclassability() {
        // Success: tests compile, failure: compilation error
        _ = _DatadogURLSessionDelegate()
    }
}
