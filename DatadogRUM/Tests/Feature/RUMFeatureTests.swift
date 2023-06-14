/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM

class RUMFeatureTests: XCTestCase {
    private var core: SingleFeatureCoreMock<RUMFeature>! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUpWithError() throws {
        core = SingleFeatureCoreMock()
    }

    override func tearDown() {
        core = nil
    }

    func testWhenNotRegisteredToCore_thenRUMMonitorIsNotAvailable() {
        // When
        XCTAssertNil(core.get(feature: RUMFeature.self))

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core) is NOPRUMMonitor)
    }

    func testWhenRegisteredToCore_thenRUMMonitorIsAvailable() throws {
        // Given
        let rum = try RUMFeature(in: core, configuration: .mockAny())

        // When
        try core.register(feature: rum)

        // Then
        XCTAssertTrue(RUMMonitor.shared(in: core) is Monitor)
    }

    func testGivenInstrumentationConfigured_whenRegistered_itSubscribesRUMMonitorToInstrumentationHandlers() throws {
        // Given
        let rum = try RUMFeature(
            in: core,
            configuration: .mockWith(
                instrumentation: .init(
                    uiKitRUMViewsPredicate: UIKitRUMViewsPredicateMock(),
                    uiKitRUMUserActionsPredicate: UIKitRUMUserActionsPredicateMock(),
                    longTaskThreshold: 0.5
                )
            )
        )

        // When
        try core.register(feature: rum)
        XCTAssertTrue(RUMMonitor.shared(in: core) is Monitor)

        // Then
        let viewsSubscriber = rum.instrumentation.viewsHandler.subscriber
        let actionsSubscriber = (rum.instrumentation.actionsHandler as? UIKitRUMUserActionsHandler)?.subscriber
        let longTasksSubscriber = rum.instrumentation.longTasks?.subscriber
        XCTAssertIdentical(viewsSubscriber, RUMMonitor.shared(in: core) as? RUMCommandSubscriber)
        XCTAssertIdentical(actionsSubscriber, RUMMonitor.shared(in: core) as? RUMCommandSubscriber)
        XCTAssertIdentical(longTasksSubscriber, RUMMonitor.shared(in: core) as? RUMCommandSubscriber)
    }

    func testGivenFirstPartyHostsConfigured_whenRegistered_itEnablesURLSessionInstrumentation() throws {
        // Given
        let rum = try RUMFeature(
            in: core,
            configuration: .mockWith(
                firstPartyHosts: .init(["foo.com": [.datadog]])
            )
        )

        // When
        try core.register(feature: rum)
        XCTAssertTrue(RUMMonitor.shared(in: core) is Monitor)

        // Then
        // TODO: RUMM-2922
        // Create mock RUMMonitor that is passed to RUMFeature(monitor:in:configuration:)
        // and assert that NetworkInstrumentationFeature was enabled in `core`.
    }

    func testGivenCustomIntakeURLConfigured_whenRegistered_itConfiguresRequestBuilder() throws {
        // TODO: RUMM-2922
    }

    func testGivenDebugRUMConfigured_whenRegistered_itEnablesDebuggingInRUMMonitor() throws {
        // TODO: RUMM-2922
    }

    func testGivenDebugRUMEnvConfigured_whenRegistered_itEnablesDebuggingInRUMMonitor() throws {
        // TODO: RUMM-2922
    }

    func testWhenRegistered_itSendsConfigurationTelemetry() throws {
        // TODO: RUMM-2922
    }

    func testItReceivesTelemetry() throws {
        // TODO: RUMM-2922
    }

    func testItReceivesErrors() throws {
        // TODO: RUMM-2922
    }

    func testItReceivesWebViewEvents() throws {
        // TODO: RUMM-2922
    }

    func testItReceivesCrashReports() throws {
        // TODO: RUMM-2922
    }
}
