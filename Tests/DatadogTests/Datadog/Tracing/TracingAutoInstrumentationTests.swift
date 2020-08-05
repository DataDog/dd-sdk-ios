/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

private struct MockURLFilter: URLFiltering {
    let allow: Bool
    func allows(_ url: URL?) -> Bool {
        return allow
    }
}

class TracingAutoInstrumentationTests: XCTestCase {
    func testInitializationWithDatadogConfiguration() throws {
        var config = Datadog.Configuration.mockAny()
        config.tracingEnabled = true
        config.tracedHosts = [String.mockAny()]
        let autoInstrumentation = TracingAutoInstrumentation(with: config)

        let urlFilter = try XCTUnwrap(autoInstrumentation?.urlFilter as? URLFilter)
        let expectedURLFilter = URLFilter(
            includedHosts: [String.mockAny()],
            excludedURLs: [
                config.logsEndpoint.url,
                config.tracesEndpoint.url,
                config.rumEndpoint.url
            ]
        )

        XCTAssertEqual(urlFilter, expectedURLFilter)
    }
}

class TracingURLSessionHooksTests: XCTestCase {
    let spanRecorder = SpanOutputMock()
    var previousSharedTracer = Global.sharedTracer

    override func setUp() {
        super.setUp()
        previousSharedTracer = Global.sharedTracer
        Global.sharedTracer = DDTracer.mockWith(spanOutput: spanRecorder)
    }

    override func tearDown() {
        super.tearDown()
        Global.sharedTracer = previousSharedTracer
    }

    let tracedHost = "foo.bar"
    let tracedRequest = URLRequest(url: URL(string: "http://foo.bar/foo")!)

    func testURLFilter() {
        let passingInterceptor = TracingAutoInstrumentation(urlFilter: MockURLFilter(allow: true))!.interceptor
        let blockingInterceptor = TracingAutoInstrumentation(urlFilter: MockURLFilter(allow: false))!.interceptor

        XCTAssertNotNil(passingInterceptor(tracedRequest))
        XCTAssertNil(blockingInterceptor(tracedRequest))
    }

    func testTaskObserver() throws {
        let interceptor = TracingAutoInstrumentation(urlFilter: MockURLFilter(allow: true))!.interceptor

        let interception = interceptor(tracedRequest)
        guard let taskObserver = interception?.taskObserver else {
            XCTFail("taskObserver should not be nil")
            return
        }

        taskObserver(.starting(tracedRequest))
        XCTAssertNil(spanRecorder.recorded)

        taskObserver(.completed(nil, nil))
        XCTAssertNotNil(spanRecorder.recorded)

        let recordedSpanTags = spanRecorder.recorded!.span.tags
        XCTAssertEqual(recordedSpanTags[OTTags.httpUrl] as? String, tracedRequest.url!.absoluteString)
        XCTAssertEqual(recordedSpanTags[OTTags.httpMethod] as? String, tracedRequest.httpMethod)
    }

    func testTaskObserver_response() throws {
        let interceptor = TracingAutoInstrumentation(urlFilter: MockURLFilter(allow: true))!.interceptor

        let interception = interceptor(tracedRequest)
        guard let taskObserver = interception?.taskObserver else {
            XCTFail("taskObserver should not be nil")
            return
        }

        taskObserver(.starting(tracedRequest))
        XCTAssertNil(spanRecorder.recorded)

        let response = HTTPURLResponse(url: tracedRequest.url!, statusCode: 404, httpVersion: nil, headerFields: nil)
        taskObserver(.completed(response, nil))
        XCTAssertNotNil(spanRecorder.recorded)

        let recordedSpanTags = spanRecorder.recorded!.span.tags
        XCTAssertEqual(recordedSpanTags[OTTags.httpStatusCode] as? Int, 404)
        XCTAssertEqual(recordedSpanTags[DDTags.resource] as? String, "404")
        XCTAssertEqual(recordedSpanTags[OTTags.error] as? Bool, true)
    }

    func testTaskObserver_NSError() throws {
        let interceptor = TracingAutoInstrumentation(urlFilter: MockURLFilter(allow: true))!.interceptor

        let interception = interceptor(tracedRequest)
        guard let taskObserver = interception?.taskObserver else {
            XCTFail("taskObserver should not be nil")
            return
        }

        taskObserver(.starting(tracedRequest))
        XCTAssertNil(spanRecorder.recorded)

        let errorDescription = "something happened"
        let error = NSError(domain: "unit-test", code: 123, userInfo: [NSLocalizedDescriptionKey: errorDescription])
        taskObserver(.completed(nil, error))
        XCTAssertNotNil(spanRecorder.recorded)

        let recordedSpanTags = spanRecorder.recorded!.span.tags
        XCTAssertEqual(recordedSpanTags[OTTags.error] as? Bool, true)
        XCTAssertEqual(recordedSpanTags[DDTags.errorType] as? String, "unit-test - 123")
        XCTAssertEqual(recordedSpanTags[DDTags.errorMessage] as? String, errorDescription)
        XCTAssertEqual(
            recordedSpanTags[DDTags.errorStack] as? String,
            #"Error Domain=unit-test Code=123 "something happened" UserInfo={NSLocalizedDescription=something happened}"#
        )
    }

    func testTaskObserver_wrongOrder() throws {
        let interceptor = TracingAutoInstrumentation(urlFilter: MockURLFilter(allow: true))!.interceptor

        let interception = interceptor(tracedRequest)
        let taskObserver: TaskObserver! = interception?.taskObserver //swiftlint:disable:this implicitly_unwrapped_optional

        for _ in 0...3 {
            taskObserver(.completed(nil, nil))
            XCTAssertNil(spanRecorder.recorded)
        }
    }

    func testTaskObserver_duplicateStarts_shouldNotFail() throws {
        let interceptor = TracingAutoInstrumentation(urlFilter: MockURLFilter(allow: true))!.interceptor

        let interception = interceptor(tracedRequest)
        let taskObserver: TaskObserver! = interception?.taskObserver //swiftlint:disable:this implicitly_unwrapped_optional

        taskObserver(.starting(tracedRequest))

        let secondRequest = URLRequest(url: URL(string: "2", relativeTo: URL(string: tracedHost))!)
        taskObserver(.starting(secondRequest))
        taskObserver(.completed(nil, nil))

        XCTAssertNotNil(spanRecorder.recorded)
        let recordedSpanTags = spanRecorder.recorded!.span.tags
        XCTAssertEqual(recordedSpanTags[OTTags.httpUrl] as? String, secondRequest.url!.absoluteString)
        XCTAssertNotEqual(recordedSpanTags[OTTags.httpUrl] as? String, tracedRequest.url!.absoluteString)
    }
}
