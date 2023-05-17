/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
@testable import DatadogRUM

class RUMInstrumentationTests: XCTestCase {
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

    /// Creates `RUMMonitor` instance for tests.
    /// The only difference vs. `RUMMonitor.initialize()` is that we disable RUM view updates sampling to get deterministic behaviour.
    private func createTestableInstrumentation(configuration: RUMConfiguration = .mockAny()) throws -> RUMInstrumentation {
        let feature = DatadogRUMFeature(in: core, configuration: configuration)
        try core.register(feature: feature)
        return feature.instrumentation
    }

    func testGivenRUMViewsAutoInstrumentationEnabled_whenRUMMonitorIsRegistered_itSubscribesAsViewsHandler() throws {
        // Given
        let instrumentation = try createTestableInstrumentation(
            configuration: .mockWith(
                instrumentation: .init(
                    uiKitRUMViewsPredicate: UIKitRUMViewsPredicateMock(),
                    uiKitRUMUserActionsPredicate: nil,
                    longTaskThreshold: nil
                )
            )
        )

        // Then
        let viewsHandler = instrumentation.viewsHandler
        XCTAssertTrue(viewsHandler.subscriber === RUMMonitor.shared(in: core))
    }

    func testGivenRUMUserActionsAutoInstrumentationEnabled_whenRUMMonitorIsRegistered_itSubscribesAsUserActionsHandler() throws {
        // Given
        let instrumentation = try createTestableInstrumentation(
            configuration: .mockWith(
                instrumentation: .init(
                    uiKitRUMViewsPredicate: nil,
                    uiKitRUMUserActionsPredicate: UIKitRUMUserActionsPredicateMock(),
                    longTaskThreshold: nil
                )
            )
        )

        // Then
        let userActionsHandler = instrumentation.userActionsAutoInstrumentation?.handler as? UIKitRUMUserActionsHandler
        XCTAssertTrue(userActionsHandler?.subscriber === RUMMonitor.shared(in: core))
    }

    func testGivenRUMLongTasksAutoInstrumentationEnabled_whenRUMMonitorIsRegistered_itSubscribesAsLongTaskObserver() throws {
        // Given
        let instrumentation = try createTestableInstrumentation(
            configuration: .mockWith(
                instrumentation: .init(
                    uiKitRUMViewsPredicate: nil,
                    uiKitRUMUserActionsPredicate: nil,
                    longTaskThreshold: 100.0
                )
            )
        )

        // Then
        XCTAssertTrue(instrumentation.longTasks?.subscriber === RUMMonitor.shared(in: core))
    }

    /// Sanity check for not-allowed configuration.
    func testWhenAllRUMAutoInstrumentationsDisabled_itDoesNotCreateInstrumentationComponents() throws {
        // Given

        // This configuration is not allowed by `FeaturesConfiguration` logic. We test it for sanity.
        let notAllowedConfiguration = RUMConfiguration.Instrumentation(
            uiKitRUMViewsPredicate: nil,
            uiKitRUMUserActionsPredicate: nil,
            longTaskThreshold: nil
        )

        let feature = DatadogRUMFeature(in: core, configuration: .mockWith(instrumentation: notAllowedConfiguration))

        // Then
        XCTAssertNil(feature.instrumentation.viewControllerSwizzler)
        XCTAssertNil(feature.instrumentation.userActionsAutoInstrumentation)
    }
}
