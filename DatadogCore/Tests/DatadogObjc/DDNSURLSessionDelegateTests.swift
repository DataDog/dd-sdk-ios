/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogCore
@testable import DatadogObjc

private class DDURLSessionDelegateMock: DDURLSessionDelegate {
    var calledDidFinishCollecting = false
    var calledDidCompleteWithError = false
    var calledDidReceiveData = false

    override func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        calledDidFinishCollecting = true
    }

    override func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        calledDidCompleteWithError = true
    }

    override func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        calledDidReceiveData = true
    }
}

class DDNSURLSessionDelegateTests: XCTestCase {
    func testInit() {
        let delegate = DDNSURLSessionDelegate()
        let url = URL(string: "foo.com")
        XCTAssertFalse(delegate.swiftDelegate.firstPartyHosts.isFirstParty(url: url))
    }

    func testInitWithAdditionalFirstPartyHosts() {
        let delegate = DDNSURLSessionDelegate(additionalFirstPartyHostsWithHeaderTypes: ["foo.com": [.datadog]])
        let url = URL(string: "http://foo.com")
        XCTAssertTrue(delegate.swiftDelegate.firstPartyHosts.isFirstParty(url: url))
    }

    func testItForwardsCallsToSwiftDelegate() {
        let swiftDelegate = DDURLSessionDelegateMock()
        let objcDelegate = DDNSURLSessionDelegate()
        objcDelegate.swiftDelegate = swiftDelegate

        objcDelegate.urlSession(.shared, task: .mockAny(), didFinishCollecting: .mockAny())
        objcDelegate.urlSession(.shared, task: .mockAny(), didCompleteWithError: ErrorMock())
        objcDelegate.urlSession(.shared, dataTask: URLSessionDataTask(), didReceive: .mockAny())

        XCTAssertTrue(swiftDelegate.calledDidFinishCollecting)
        XCTAssertTrue(swiftDelegate.calledDidCompleteWithError)
        XCTAssertTrue(swiftDelegate.calledDidReceiveData)
    }
}
