/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class TracingAutoInstrumentationTests: XCTestCase {
    func testFailableInit() {
        XCTAssertNil(TracingAutoInstrumentation(tracedHosts: []))
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

    let tracedHost = URL(string: "http://foo.bar")!
    let tracedRequest = URLRequest(url: URL(string: "http://foo.bar/foo")!)

    func testTracedHosts() {
        let interceptor: RequestInterceptor = TracingRequestInterceptor.build(with: [tracedHost])

        XCTAssertNotNil(interceptor(tracedRequest))

        let urlInNonTracedHost = URL(string: "http://www.foo.bar/foo")!
        XCTAssertNil(interceptor(URLRequest(url: urlInNonTracedHost)))

        let complexURLInTracedHost = URL(string: "http://johnny:p4ssw0rd@foo.bar:999/script.ext;param=value?query=value#ref")!
        XCTAssertNotNil(interceptor(URLRequest(url: complexURLInTracedHost)))

        let differentSchemeInTracedHost = URL(string: "https://foo.bar/foo")!
        XCTAssertNil(interceptor(URLRequest(url: differentSchemeInTracedHost)))
    }

    func testTaskObserver() throws {
        let interceptor: RequestInterceptor = TracingRequestInterceptor.build(with: [tracedHost])

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
        let interceptor: RequestInterceptor = TracingRequestInterceptor.build(with: [tracedHost])

        let interception = interceptor(tracedRequest)
        guard let taskObserver = interception?.taskObserver else {
            XCTFail("taskObserver should not be nil")
            return
        }

        taskObserver(.starting(tracedRequest))
        XCTAssertNil(spanRecorder.recorded)

        let response = HTTPURLResponse(url: tracedRequest.url!, statusCode: 999, httpVersion: nil, headerFields: nil)
        taskObserver(.completed(response, nil))
        XCTAssertNotNil(spanRecorder.recorded)

        let recordedSpanTags = spanRecorder.recorded!.span.tags
        XCTAssertEqual(recordedSpanTags[OTTags.httpStatusCode] as? Int, 999)
    }

    func testTaskObserver_NSError() throws {
        let interceptor: RequestInterceptor = TracingRequestInterceptor.build(with: [tracedHost])

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
        XCTAssertEqual(recordedSpanTags[DDTags.errorType] as? String, "\(error.domain) - \(error.code)")
        XCTAssertEqual(recordedSpanTags[DDTags.errorMessage] as? String, errorDescription)
        XCTAssertEqual(recordedSpanTags[DDTags.errorStack] as? String, String(describing: error))
    }

    func testTaskObserver_wrongOrder() throws {
        let interceptor: RequestInterceptor = TracingRequestInterceptor.build(with: [tracedHost])

        let interception = interceptor(tracedRequest)
        let taskObserver: TaskObserver! = interception?.taskObserver //swiftlint:disable:this implicitly_unwrapped_optional

        for _ in 0...3 {
            taskObserver(.completed(nil, nil))
            XCTAssertNil(spanRecorder.recorded)
        }
    }

    func testTaskObserver_duplicateStarts_shouldNotFail() throws {
        let interceptor: RequestInterceptor = TracingRequestInterceptor.build(with: [tracedHost])

        let interception = interceptor(tracedRequest)
        let taskObserver: TaskObserver! = interception?.taskObserver //swiftlint:disable:this implicitly_unwrapped_optional

        taskObserver(.starting(tracedRequest))

        let secondRequest = URLRequest(url: URL(string: "2", relativeTo: tracedHost)!)
        taskObserver(.starting(secondRequest))
        taskObserver(.completed(nil, nil))

        XCTAssertNotNil(spanRecorder.recorded)
        let recordedSpanTags = spanRecorder.recorded!.span.tags
        XCTAssertEqual(recordedSpanTags[OTTags.httpUrl] as? String, secondRequest.url!.absoluteString)
        XCTAssertNotEqual(recordedSpanTags[OTTags.httpUrl] as? String, tracedRequest.url!.absoluteString)
    }
}
