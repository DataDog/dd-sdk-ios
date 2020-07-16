/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import Datadog

class RUMMonitorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(RUMFeature.instance)
        temporaryDirectory.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(RUMFeature.instance)
        temporaryDirectory.delete()
        super.tearDown()
    }

    // MARK: - Sending RUM events

    func testWhenFirstViewIsStarted_itSendsApplicationStartAction() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.start(view: UIViewController(), attributes: nil)

        let rumEventMatcher = try server.waitAndReturnRUMEventMatchers(count: 1)[0]

        let event: RUMActionEvent = try rumEventMatcher.model()
        XCTAssertEqual(event.application.id, "abc-123")
        XCTAssertEqual(event.action.type, "application_start")
        XCTAssertEqual(event.view.id, "00000000-0000-0000-0000-000000000000")
        XCTAssertEqual(event.view.url, "")
        XCTAssertNotEqual(event.session.id, "00000000-0000-0000-0000-000000000000")
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockNoOp(temporaryDirectory: temporaryDirectory)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: .mockAny())
        let mockView = UIViewController()

        DispatchQueue.concurrentPerform(iterations: 900) { iteration in
            let modulo = iteration % 9

            switch modulo {
            case 0: monitor.start(view: mockView, attributes: nil)
            case 1: monitor.stop(view: mockView, attributes: nil)
            case 2: monitor.addViewError(message: .mockAny(), error: ErrorMock(), attributes: nil)
            case 3: monitor.start(resource: .mockAny(), attributes: nil)
            case 4: monitor.stop(resource: .mockAny(), attributes: nil)
            case 5: monitor.stop(resource: .mockAny(), withError: ErrorMock(), attributes: nil)
            case 6: monitor.start(userAction: .scroll, attributes: nil)
            case 7: monitor.stop(userAction: .scroll, attributes: nil)
            case 8: monitor.add(userAction: .tap, attributes: nil)
            default: break
            }
        }

        server.waitAndAssertNoRequestsSent()
    }

    // MARK: - Usage

    func testWhenCallingPublicAPI_itProcessessExpectedCommandsThrougScopes() {
        let scope = RUMScopeMock()
        let monitor = RUMMonitor(applicationScope: scope)

        let mockView = UIViewController()
        let mockAttributes = ["foo": "bar"]
        let mockError = ErrorMock()

        // TODO: RUMM-585 Replace these internal API calls with public APIs
        monitor.start(view: mockView, attributes: mockAttributes)
        monitor.stop(view: mockView, attributes: mockAttributes)
        monitor.addViewError(message: "error", error: mockError, attributes: mockAttributes)

        monitor.start(resource: "/resource/1", attributes: mockAttributes)
        monitor.stop(resource: "/resource/1", attributes: mockAttributes)
        monitor.stop(resource: "/resource/1", withError: ErrorMock(), attributes: mockAttributes)

        monitor.start(userAction: .scroll, attributes: mockAttributes)
        monitor.stop(userAction: .scroll, attributes: mockAttributes)
        monitor.add(userAction: .tap, attributes: mockAttributes)

        let recordedCommands = scope.waitAndReturnProcessedCommands(count: 9, timeout: 0.5)

        XCTAssertEqual(
            recordedCommands,
            [
                .startView(id: mockView, attributes: mockAttributes),
                .stopView(id: mockView, attributes: mockAttributes),
                .addCurrentViewError(message: "error", error: mockError, attributes: mockAttributes),
                .startResource(resourceName: "/resource/1", attributes: mockAttributes),
                .stopResource(resourceName: "/resource/1", attributes: mockAttributes),
                .stopResourceWithError(resourceName: "/resource/1", error: mockError, attributes: mockAttributes),
                .startUserAction(userAction: .scroll, attributes: mockAttributes),
                .stopUserAction(userAction: .scroll, attributes: mockAttributes),
                .addUserAction(userAction: .tap, attributes: mockAttributes)
            ]
        )
    }
}
