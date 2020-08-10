/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class LoggingWithRUMContextIntegrationTests: XCTestCase {
    private let integration = LoggingWithRUMContextIntegration()

    func testWhenRUMMonitorIsRegistered_itProvidesRUMContextAttributesForLogs() throws {
        RUMFeature.instance = .mockNoOp(temporaryDirectory: temporaryDirectory)
        defer { RUMFeature.instance = nil }

        // when
        let monitor = RUMMonitor.initialize(rumApplicationID: "rum-123")
        monitor.startView(viewController: mockView)

        // then
        let logAttributes = try XCTUnwrap(integration.currentRUMContextAttributes)

        XCTAssertEqual(logAttributes.count, 3)
        XCTAssertEqual(logAttributes["application_id"] as? String, "rum-123")
        XCTAssertValidRumUUID(logAttributes["session_id"] as? String)
        XCTAssertValidRumUUID(logAttributes["view.id"] as? String)
    }

    func testWhenRUMMonitorIsNotRegistered_itPrintsUserWarningWhenRequestingRUMContextAttributesForLogs() throws {
        RUMFeature.instance = .mockNoOp(temporaryDirectory: temporaryDirectory)
        defer { RUMFeature.instance = nil }

        let previousUserLogger = userLogger
        defer { userLogger = previousUserLogger }

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        // when
        XCTAssertNil(RUMMonitor.shared)

        // then
        XCTAssertNil(integration.currentRUMContextAttributes)
        XCTAssertEqual(output.recordedLog?.level, .warn)
        try XCTAssertTrue(
            XCTUnwrap(output.recordedLog?.message)
                .contains("No `RUMMonitor` is registered, so RUM integration with Logging will not work.")
        )
    }
}

class LoggingWithRUMErrorsIntegrationTests: XCTestCase {
    private let integration = LoggingWithRUMErrorsIntegration()

    override class func setUp() {
        super.setUp()
        temporaryDirectory.create()
    }

    override class func tearDown() {
        super.tearDown()
        temporaryDirectory.delete()
    }

    func testGivenRUMMonitorRegistered_whenLoggignErrorMessage_itSendsRUMErrorForCurrentView() throws {
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
        integration.addError(with: "log error message")

        // then
        let rumEventMatchers = try server.waitAndReturnRUMEventMatchers(count: 3) // [RUMView, RUMAction, RUMError] events sent
        let rumErrorMatcher = rumEventMatchers.first { $0.model(isTypeOf: RUMError.self) }
        try XCTUnwrap(rumErrorMatcher).model(ofType: RUMError.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "log error message")
            XCTAssertEqual(rumModel.error.source, .logger)
            XCTAssertNil(rumModel.error.stack)
        }
    }
}
