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

@available(*, deprecated)
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

@available(*, deprecated)
class DDNSURLSessionDelegateTests: XCTestCase {
    private var core: FeatureRegistrationCoreMock! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()

        core = FeatureRegistrationCoreMock()
        CoreRegistry.register(default: core)

        let config = DDRUMConfiguration(applicationID: "fake-id")
        config.setURLSessionTracking(.init())
        DDRUM.enable(with: config)
    }

    override func tearDown() {
        DDURLSessionInstrumentation.disable(delegateClass: DDNSURLSessionDelegate.self)
        CoreRegistry.unregisterDefault()
        core = nil

        super.tearDown()
    }

    func testInit() {
        _ = DDNSURLSessionDelegate()
    }

    func testInitWithAdditionalFirstPartyHostsWithHeaderTypes() {
        _ = DDNSURLSessionDelegate(additionalFirstPartyHostsWithHeaderTypes: ["foo.com": [.datadog]])
    }

    func testInitWithAdditionalFirstPartyHosts() {
        _ = DDNSURLSessionDelegate(additionalFirstPartyHosts: ["foo.com"])
    }
}
