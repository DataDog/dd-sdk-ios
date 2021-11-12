/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMInstrumentationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(RUMFeature.instance)
        XCTAssertNil(RUMInstrumentation.instance)
    }

    override func tearDown() {
        XCTAssertNil(RUMInstrumentation.instance)
        XCTAssertNil(RUMFeature.instance)
        super.tearDown()
    }

    func testGivenRUMViewsAutoInstrumentationEnabled_whenRUMMonitorIsRegistered_itSubscribesAsViewsHandler() throws {
        // Given
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance?.deinitialize() }

        RUMInstrumentation.instance = RUMInstrumentation(
            configuration: .init(
                uiKitRUMViewsPredicate: UIKitRUMViewsPredicateMock(),
                uiKitRUMUserActionsPredicate: nil,
                longTaskThreshold: nil
            ),
            dateProvider: SystemDateProvider()
        )
        defer { RUMInstrumentation.instance?.deinitialize() }

        // When
        Global.rum = RUMMonitor.initialize()
        defer { Global.rum = DDNoopRUMMonitor() }

        // Then
        let viewsHandler = RUMInstrumentation.instance?.viewsHandler
        XCTAssertTrue(viewsHandler?.subscriber === Global.rum)
    }

    func testGivenRUMUserActionsAutoInstrumentationEnabled_whenRUMMonitorIsRegistered_itSubscribesAsUserActionsHandler() throws {
        // Given
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance?.deinitialize() }

        RUMInstrumentation.instance = RUMInstrumentation(
            configuration: .init(
                uiKitRUMViewsPredicate: nil,
                uiKitRUMUserActionsPredicate: UIKitRUMUserActionsPredicateMock(),
                longTaskThreshold: nil
            ),
            dateProvider: SystemDateProvider()
        )
        defer { RUMInstrumentation.instance?.deinitialize() }

        // When
        Global.rum = RUMMonitor.initialize()
        defer { Global.rum = DDNoopRUMMonitor() }

        // Then
        let userActionsHandler = RUMInstrumentation.instance?.userActionsAutoInstrumentation?.handler as? UIKitRUMUserActionsHandler
        XCTAssertTrue(userActionsHandler?.subscriber === Global.rum)
    }

    func testGivenRUMLongTasksAutoInstrumentationEnabled_whenRUMMonitorIsRegistered_itSubscribesAsLongTaskObserver() throws {
        // Given
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance?.deinitialize() }

        RUMInstrumentation.instance = RUMInstrumentation(
            configuration: .init(
                uiKitRUMViewsPredicate: nil,
                uiKitRUMUserActionsPredicate: nil,
                longTaskThreshold: 100.0
            ),
            dateProvider: SystemDateProvider()
        )
        defer { RUMInstrumentation.instance?.deinitialize() }

        // When
        Global.rum = RUMMonitor.initialize()
        defer { Global.rum = DDNoopRUMMonitor() }

        // Then
        XCTAssertTrue(RUMInstrumentation.instance?.longTasks?.subscriber === Global.rum)
    }

    /// Sanity check for not-allowed configuration.
    func testWhenAllRUMAutoInstrumentationsDisabled_itDoesNotCreateInstrumentationComponents() throws {
        // Given
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance?.deinitialize() }

        /// This configuration is not allowed by `FeaturesConfiguration` logic. We test it for sanity.
        let notAllowedConfiguration = FeaturesConfiguration.RUM.Instrumentation(
            uiKitRUMViewsPredicate: nil,
            uiKitRUMUserActionsPredicate: nil,
            longTaskThreshold: nil
        )

        RUMInstrumentation.instance = RUMInstrumentation(
            configuration: notAllowedConfiguration,
            dateProvider: SystemDateProvider()
        )
        defer { RUMInstrumentation.instance?.deinitialize() }

        // Then
        XCTAssertNil(RUMInstrumentation.instance?.viewControllerSwizzler)
        XCTAssertNil(RUMInstrumentation.instance?.userActionsAutoInstrumentation)
    }
}
