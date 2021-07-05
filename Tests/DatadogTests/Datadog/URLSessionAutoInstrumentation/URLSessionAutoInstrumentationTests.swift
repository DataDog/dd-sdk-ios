/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class URLSessionAutoInstrumentationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(URLSessionAutoInstrumentation.instance)
    }

    override func tearDown() {
        XCTAssertNil(URLSessionAutoInstrumentation.instance)
        super.tearDown()
    }

    func testWhenURLSessionAutoInstrumentationIsEnabled_thenSharedIntrceptorIsAvailable() {
        XCTAssertNil(URLSessionInterceptor.shared)

        // When
        URLSessionAutoInstrumentation.instance = URLSessionAutoInstrumentation(
            configuration: .mockAny(),
            dateProvider: SystemDateProvider(),
            appStateListener: AppStateListener.mockAny()
        )
        defer {
            URLSessionAutoInstrumentation.instance?.swizzler.unswizzle()
            URLSessionAutoInstrumentation.instance?.deinitialize()
        }

        // Then
        XCTAssertNotNil(URLSessionInterceptor.shared)
    }

    func testGivenURLSessionAutoInstrumentationEnabled_whenRUMMonitorIsRegistered_itSubscribesAsResourcesHandler() throws {
        // Given
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance?.deinitialize() }

        URLSessionAutoInstrumentation.instance = URLSessionAutoInstrumentation(
            configuration: .mockAny(),
            dateProvider: SystemDateProvider(),
            appStateListener: AppStateListener.mockAny()
        )
        defer {
            URLSessionAutoInstrumentation.instance?.swizzler.unswizzle()
            URLSessionAutoInstrumentation.instance?.deinitialize()
        }

        // When
        Global.rum = RUMMonitor.initialize()
        defer { Global.rum = DDNoopRUMMonitor() }

        // Then
        let resourcesHandler = URLSessionAutoInstrumentation.instance?.interceptor.handler as? URLSessionRUMResourcesHandler
        XCTAssertTrue(resourcesHandler?.subscriber === Global.rum)
    }
}
