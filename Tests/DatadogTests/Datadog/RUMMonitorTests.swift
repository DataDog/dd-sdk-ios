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

    func testStartingView() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        let dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
        RUMFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            dateProvider: dateProvider
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.startView(viewController: mockView)
        monitor.stopView(viewController: mockView)
        monitor.startView(viewController: mockView)

        let rumEventMatchers = try server.waitAndReturnRUMEventMatchers(count: 4)
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, "application_start")
        }
        try rumEventMatchers[1].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
        }
        try rumEventMatchers[2].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.timeSpent, 1_000_000_000)
        }
        try rumEventMatchers[3].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 0)
        }
    }

    func testStartingView_thenLoadingResource() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceName: "/resource/1", request: .mockAny())
        monitor.stopResourceLoading(resourceName: "/resource/1", response: .mockResponseWith(statusCode: 200))

        let rumEventMatchers = try server.waitAndReturnRUMEventMatchers(count: 4)
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, "application_start")
        }
        try rumEventMatchers[1].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 1)
        }
        try rumEventMatchers[3].model(ofType: RUMResourceEvent.self) { rumModel in
            XCTAssertEqual(rumModel.resource.statusCode, 200)
        }
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
            case 3: monitor.start(resource: .mockAny(), url: .mockAny(), httpMethod: .mockAny(), attributes: nil)
            case 4: monitor.stop(resource: .mockAny(), type: .mockAny(), httpStatusCode: 200, size: 0, attributes: nil)
            case 5: monitor.stop(resource: .mockAny(), withError: .mockAny(), errorSource: .mockAny(), httpStatusCode: 400, attributes: nil)
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
        let mockError = ErrorMock()

        // TODO: RUMM-585 Replace these internal API calls with public APIs
        monitor.start(view: mockView, attributes: nil)
        monitor.stop(view: mockView, attributes: nil)
        monitor.addViewError(message: .mockAny(), error: mockError, attributes: nil)

        monitor.start(resource: .mockAny(), url: .mockAny(), httpMethod: .mockAny(), attributes: nil)
        monitor.stop(resource: .mockAny(), type: .mockAny(), httpStatusCode: 200, size: 0, attributes: nil)
        monitor.stop(resource: .mockAny(), withError: .mockAny(), errorSource: .mockAny(), httpStatusCode: 400, attributes: nil)

        monitor.start(userAction: .scroll, attributes: nil)
        monitor.stop(userAction: .scroll, attributes: nil)
        monitor.add(userAction: .tap, attributes: nil)

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
