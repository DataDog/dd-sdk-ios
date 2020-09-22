/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMAutoInstrumentationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(RUMFeature.instance)
        XCTAssertNil(RUMAutoInstrumentation.instance)
    }

    override func tearDown() {
        XCTAssertNil(RUMAutoInstrumentation.instance)
        XCTAssertNil(RUMFeature.instance)
        super.tearDown()
    }

    func testGivenRUMAutoInstrumentationEnabled_whenRUMMonitorIsRegistered_itSubscribesAsViewsHandler() throws {
        // Given
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance = nil }

        RUMAutoInstrumentation.instance = RUMAutoInstrumentation(
            configuration: .init(uiKitRUMViewsPredicate: UIKitRUMViewsPredicateMock()),
            dateProvider: SystemDateProvider()
        )
        defer { RUMAutoInstrumentation.instance = nil }

        // When
        Global.rum = RUMMonitor.initialize()
        defer { Global.rum = DDNoopRUMMonitor() }

        // Then
        let viewsHandler = RUMAutoInstrumentation.instance?.views?.handler as? UIKitRUMViewsHandler
        XCTAssertTrue(viewsHandler?.subscriber === Global.rum)
    }
}
