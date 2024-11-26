/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

import TestUtilities
@testable import DatadogInternal

class URLSessionInterceptorTests: XCTestCase {
    // swiftlint:disable implicitly_unwrapped_optional
    private var core: SingleFeatureCoreMock<NetworkInstrumentationFeature>!
    private var handler: URLSessionHandlerMock!
    // swiftlint:enable implicitly_unwrapped_optional

    override func setUpWithError() throws {
        try super.setUpWithError()

        core = SingleFeatureCoreMock()
        handler = URLSessionHandlerMock()
        try core.register(urlSessionHandler: handler)
    }

    override func tearDown() {
        core = nil
        super.tearDown()
    }

    func testTraceInterception() throws {
        // Given
        let feature = try XCTUnwrap(core.get(feature: NetworkInstrumentationFeature.self))
        let trace: TraceContext = .mockWith(isKept: true)
        let writer: TracePropagationHeadersWriter = oneOf([
            { HTTPHeadersWriter(samplingStrategy: .headBased, traceContextInjection: .all) },
            { B3HTTPHeadersWriter(samplingStrategy: .custom(sampleRate: 100)) },
            { W3CHTTPHeadersWriter(samplingStrategy: .headBased) }
        ])

        let url: URL = .mockAny()
        handler.firstPartyHosts = .init(
            hostsWithTracingHeaderTypes: [url.host!: [.datadog]]
        )

        writer.write(traceContext: trace)
        handler.modifiedRequest = .mockWith(url: url, headers: writer.traceHeaderFields)
        handler.injectedTraceContext = trace

        // When
        var interceptor = try XCTUnwrap(URLSessionInterceptor.shared(in: core))
        let request = interceptor.intercept(request: .mockWith(url: url))

        let task: URLSessionTask = .mockWith(request: request)
        interceptor = try XCTUnwrap(URLSessionInterceptor.shared(in: core))
        interceptor.intercept(task: task)

        interceptor = try XCTUnwrap(URLSessionInterceptor.shared(in: core))
        interceptor.task(task, didCompleteWithError: nil)

        handler.onInterceptionDidStart = { interception in
            // Then
            XCTAssertEqual(interception.trace, trace)
        }

        feature.flush()

        XCTAssert(URLSessionInterceptor.contextsByTraceID.isEmpty)
    }
}
