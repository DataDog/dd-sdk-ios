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

    func testWhenFirstViewIsStarted_itSendsApplicationStartActionAndViewEvent() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.start(view: UIViewController(), attributes: ["foo": "bar"])

        let rumEventMatchers = try server.waitAndReturnRUMEventMatchers(count: 2)
        let applicationStartAction: RUMActionEvent = try rumEventMatchers[0].model()
        let viewEvent: RUMViewEvent = try rumEventMatchers[1].model()

        XCTAssertEqual(applicationStartAction.action.type, "application_start")
        XCTAssertEqual(viewEvent.view.action.count, 1)
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

    func testWhenCallingPublicAPI_itProcessesExpectedCommandsThrougScopes() {
        let scope = RUMScopeMock()
        let dateProvider = RelativeDateProvider(using: .mockDecember15th2019At10AMUTC())
        let monitor = RUMMonitor(applicationScope: scope, dateProvider: dateProvider)

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

        let commands = scope.waitAndReturnProcessedCommands(count: 9, timeout: 0.5)

        XCTAssertTrue(commands[0] is RUMStartViewCommand)
        XCTAssertTrue(commands[1] is RUMStopViewCommand)
        XCTAssertTrue(commands[2] is RUMAddCurrentViewErrorCommand)
        XCTAssertTrue(commands[3] is RUMStartResourceCommand)
        XCTAssertTrue(commands[4] is RUMStopResourceCommand)
        XCTAssertTrue(commands[5] is RUMStopResourceWithErrorCommand)
        XCTAssertTrue(commands[6] is RUMStartUserActionCommand)
        XCTAssertTrue(commands[7] is RUMStopUserActionCommand)
        XCTAssertTrue(commands[8] is RUMAddUserActionCommand)
    }
}
