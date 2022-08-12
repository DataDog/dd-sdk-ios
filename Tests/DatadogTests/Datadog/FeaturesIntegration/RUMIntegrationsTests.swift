/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMIntegrationsTests: XCTestCase {
    let core = DatadogCoreMock()

    private let integration = RUMContextIntegration()

    override func tearDown() {
        core.flush()
        super.tearDown()
    }

    func testGivenRUMMonitorRegistered_itProvidesRUMContextAttributes() throws {
        let rum: RUMFeature = .mockNoOp()
        core.register(feature: rum)

        // given
        Global.rum = RUMMonitor.initialize(in: core)
        Global.rum.startView(viewController: mockView)
        Global.rum.startUserAction(type: .tap, name: .mockAny())
        defer { Global.rum = DDNoopRUMMonitor() }

        // then
        let attributes = try XCTUnwrap(integration.currentRUMContextAttributes)

        XCTAssertEqual(attributes.count, 4)
        XCTAssertEqual(
            attributes["application_id"] as? String,
            rum.configuration.applicationID
        )
        XCTAssertValidRumUUID(attributes["session_id"] as? String)
        XCTAssertValidRumUUID(attributes["view.id"] as? String)
        XCTAssertValidRumUUID(attributes["user_action.id"] as? String)
    }

    func testGivenRUMMonitorRegistered_whenSessionIsRejectedBySampler_itProvidesEmptyRUMContextAttributes() throws {
        let rum = RUMFeature(
            storage: .mockNoOp(),
            upload: .mockNoOp(),
            configuration: .mockWith(sessionSampler: .mockRejectAll()),
            messageReceiver: NOOPFeatureMessageReceiver()
        )
        core.register(feature: rum)

        // given
        Global.rum = RUMMonitor.initialize(in: core)
        Global.rum.startView(viewController: mockView)
        defer { Global.rum = DDNoopRUMMonitor() }

        // then
        let attributes = try XCTUnwrap(integration.currentRUMContextAttributes)

        XCTAssertTrue(attributes.isEmpty)
    }

    func testWhenRUMMonitorIsNotRegistered_itReturnsNil() throws {
        // when
        XCTAssertTrue(Global.rum is DDNoopRUMMonitor)

        // then
        XCTAssertNil(integration.currentRUMContextAttributes)
    }
}

class RUMErrorsIntegrationTests: XCTestCase {
    let integration = RUMErrorsIntegration()

    func testGivenRUMMonitorRegistered_whenAddingErrorMessage_itSendsRUMErrorForCurrentView() throws {
        let core = DatadogCoreMock()
        defer { core.flush() }

        let rum: RUMFeature = .mockByRecordingRUMEventMatchers()
        core.register(feature: rum)

        // given
        Global.rum = RUMMonitor.initialize(in: core)
        Global.rum.startView(viewController: mockView)
        defer { Global.rum = DDNoopRUMMonitor() }

        // when
        integration.addError(with: "error message", type: "Error type", stack: "Foo.swift:10", source: .logger)

        // then
        let rumEventMatchers = try rum.waitAndReturnRUMEventMatchers(count: 3) // [RUMView, RUMAction, RUMError] events sent
        let rumErrorMatcher = rumEventMatchers.first { $0.model(isTypeOf: RUMErrorEvent.self) }
        try XCTUnwrap(rumErrorMatcher).model(ofType: RUMErrorEvent.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "error message")
            XCTAssertEqual(rumModel.error.type, "Error type")
            XCTAssertEqual(rumModel.error.source, .logger)
            XCTAssertEqual(rumModel.error.stack, "Foo.swift:10")
        }
    }
}
