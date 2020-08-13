/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMIntegrationsTests: XCTestCase {
    private let integration = RUMContextIntegration()

    func testWhenRUMMonitorIsRegistered_itProvidesRUMContextAttributes() throws {
        RUMFeature.instance = .mockNoOp(temporaryDirectory: temporaryDirectory)
        defer { RUMFeature.instance = nil }

        // when
        let monitor = RUMMonitor.initialize(rumApplicationID: "rum-123")
        monitor.startView(viewController: mockView)

        // then
        let attributes = try XCTUnwrap(integration.currentRUMContextAttributes)

        XCTAssertEqual(attributes.count, 3)
        XCTAssertEqual(attributes["application_id"] as? String, "rum-123")
        XCTAssertValidRumUUID(attributes["session_id"] as? String)
        XCTAssertValidRumUUID(attributes["view.id"] as? String)
    }

    func testWhenRUMMonitorIsNotRegistered_itReturnsNil() throws {
        RUMFeature.instance = .mockNoOp(temporaryDirectory: temporaryDirectory)
        defer { RUMFeature.instance = nil }

        // when
        XCTAssertNil(RUMMonitor.shared)

        // then
        XCTAssertNil(integration.currentRUMContextAttributes)
    }
}

class RUMErrorsIntegrationTests: XCTestCase {
    private let integration = RUMErrorsIntegration()

    override class func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override class func tearDown() {
        super.tearDown()
        temporaryDirectory.delete()
    }

    func testGivenRUMMonitorRegistered_whenAddingErrorMessage_itSendsRUMErrorForCurrentView() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { RUMFeature.instance = nil }

        // given
        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")
        monitor.startView(viewController: mockView)

        // when
        integration.addError(with: "error message")

        // then
        let rumEventMatchers = try server.waitAndReturnRUMEventMatchers(count: 3) // [RUMView, RUMAction, RUMError] events sent
        let rumErrorMatcher = rumEventMatchers.first { $0.model(isTypeOf: RUMError.self) }
        try XCTUnwrap(rumErrorMatcher).model(ofType: RUMError.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "error message")
            XCTAssertEqual(rumModel.error.source, .logger)
            XCTAssertNil(rumModel.error.stack)
        }
    }
}
