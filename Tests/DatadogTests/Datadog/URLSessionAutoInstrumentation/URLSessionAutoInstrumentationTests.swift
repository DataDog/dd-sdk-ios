/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class URLSessionAutoInstrumentationTests: XCTestCase {
    let core = DatadogCoreMock()

    override func setUp() {
        super.setUp()
        XCTAssertNil(URLSessionAutoInstrumentation.instance)
    }

    override func tearDown() {
        core.flush()
        XCTAssertNil(URLSessionAutoInstrumentation.instance)
        super.tearDown()
    }

    func testWhenURLSessionAutoInstrumentationIsEnabled_thenSharedInterceptorIsAvailable() {
        XCTAssertNil(URLSessionInterceptor.shared)

        // When
        URLSessionAutoInstrumentation.instance = URLSessionAutoInstrumentation(
            configuration: .mockAny(),
            commonDependencies: .mockAny()
        )
        defer {
            URLSessionAutoInstrumentation.instance?.deinitialize()
        }

        // Then
        XCTAssertNotNil(URLSessionInterceptor.shared)
    }

    func testGivenURLSessionAutoInstrumentationEnabled_whenRUMMonitorIsRegistered_itSubscribesAsResourcesHandler() throws {
        // Given
        let rum: RUMFeature = .mockNoOp()
        core.registerFeature(named: RUMFeature.featureName, instance: rum)

        URLSessionAutoInstrumentation.instance = URLSessionAutoInstrumentation(
            configuration: .mockAny(),
            commonDependencies: .mockAny()
        )
        defer { URLSessionAutoInstrumentation.instance?.deinitialize() }

        // When
        Global.rum = RUMMonitor.initialize(in: core)
        defer { Global.rum = DDNoopRUMMonitor() }

        // Then
        let resourcesHandler = URLSessionAutoInstrumentation.instance?.interceptor.handler as? URLSessionRUMResourcesHandler
        XCTAssertTrue(resourcesHandler?.subscriber === Global.rum)
    }
}
