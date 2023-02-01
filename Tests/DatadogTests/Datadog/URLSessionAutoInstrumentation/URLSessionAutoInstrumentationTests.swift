/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import Datadog

class URLSessionAutoInstrumentationTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    func testWhenURLSessionAutoInstrumentationIsEnabled_thenSharedInterceptorIsAvailable() {
        defaultDatadogCore = core
        defer { defaultDatadogCore = NOPDatadogCore() }

        XCTAssertNil(URLSessionInterceptor.shared)

        // When
        let instrumentation = URLSessionAutoInstrumentation(
            configuration: .mockAny(),
            dateProvider: SystemDateProvider(),
            appStateListener: AppStateListenerMock.mockAny()
        )

        core.register(feature: instrumentation)

        // Then
        XCTAssertNotNil(URLSessionInterceptor.shared)
    }

    func testGivenURLSessionAutoInstrumentationEnabled_whenRUMMonitorIsRegistered_itSubscribesAsResourcesHandler() throws {
        // Given
        let rum: RUMFeature = .mockAny()
        let instrumentation = URLSessionAutoInstrumentation(
            configuration: .mockAny(),
            dateProvider: SystemDateProvider(),
            appStateListener: AppStateListenerMock.mockAny()
        )

        core.register(feature: rum)
        core.register(feature: instrumentation)

        // When
        Global.rum = RUMMonitor.initialize(in: core)
        defer { Global.rum = DDNoopRUMMonitor() }

        // Then
        let resourcesHandler = instrumentation?.interceptor.handler as? URLSessionRUMResourcesHandler
        XCTAssertTrue(resourcesHandler?.subscriber === Global.rum)
    }
}
