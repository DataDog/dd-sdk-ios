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
        monitor.startResourceLoading(resourceName: "/resource/1", url: .mockAny(), httpMethod: .mockAny())
        monitor.stopResourceLoading(resourceName: "/resource/1", kind: .image, httpStatusCode: 200)

        let rumEventMatchers = try server.waitAndReturnRUMEventMatchers(count: 4)
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, "application_start")
        }
        try rumEventMatchers[1].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMResource.self) { rumModel in
            XCTAssertEqual(rumModel.resource.type, .image)
            XCTAssertEqual(rumModel.resource.statusCode, 200)
        }
        try rumEventMatchers[3].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 1)
        }
    }

    func testStartingView_thenTappingButton() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.startView(viewController: mockView)
        monitor.registerUserAction(type: .tap)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try server.waitAndReturnRUMEventMatchers(count: 4)
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, "application_start")
        }
        try rumEventMatchers[1].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, "tap")
        }
        try rumEventMatchers[3].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 2)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
    }

    func testStartingView_thenLoadingResources_whileScrolling() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll)
        monitor.startResourceLoading(resourceName: "/resource/1", url: .mockAny(), httpMethod: .GET)
        monitor.stopResourceLoading(resourceName: "/resource/1", kind: .image, httpStatusCode: 200)
        monitor.startResourceLoading(resourceName: "/resource/2", url: .mockAny(), httpMethod: .GET)
        monitor.stopResourceLoading(resourceName: "/resource/2", kind: .image, httpStatusCode: 202)
        monitor.stopUserAction(type: .scroll)

        let rumEventMatchers = try server.waitAndReturnRUMEventMatchers(count: 8)
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, "application_start")
        }
        try rumEventMatchers[1].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMResource.self) { rumModel in
            XCTAssertEqual(rumModel.resource.statusCode, 200)
        }
        try rumEventMatchers[3].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 1)
        }
        try rumEventMatchers[4].model(ofType: RUMResource.self) { rumModel in
            XCTAssertEqual(rumModel.resource.statusCode, 202)
        }
        try rumEventMatchers[5].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 2)
        }
        try rumEventMatchers[6].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.resource?.count, 2)
            XCTAssertEqual(rumModel.action.error?.count, 0)
        }
        try rumEventMatchers[7].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 2)
            XCTAssertEqual(rumModel.view.resource.count, 2)
        }
    }

    func testStartingView_thenIssuingAnError_whileScrolling() throws {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockWorkingFeatureWith(
            server: server,
            directory: temporaryDirectory,
            dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 0.01)
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll)
        #sourceLocation(file: "/user/abc/Foo.swift", line: 100)
        monitor.addViewError(message: "View error message", source: .source)
        #sourceLocation()
        monitor.stopUserAction(type: .scroll)

        let rumEventMatchers = try server.waitAndReturnRUMEventMatchers(count: 6)
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, "application_start")
        }
        try rumEventMatchers[1].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMError.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "View error message")
            XCTAssertEqual(rumModel.error.stack, "Foo.swift: 100")
            XCTAssertEqual(rumModel.error.source, .source)
        }
        try rumEventMatchers[3].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
            XCTAssertEqual(rumModel.view.error.count, 1)
        }
        try rumEventMatchers[4].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, "scroll")
            XCTAssertEqual(rumModel.action.error?.count, 1)
        }
        try rumEventMatchers[5].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 2)
            XCTAssertEqual(rumModel.view.resource.count, 0)
            XCTAssertEqual(rumModel.view.error.count, 1)
        }
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        let server = ServerMock(delivery: .success(response: .mockResponseWith(statusCode: 200)))
        RUMFeature.instance = .mockNoOp(temporaryDirectory: temporaryDirectory)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: .mockAny())
        let view = mockView

        DispatchQueue.concurrentPerform(iterations: 900) { iteration in
            let modulo = iteration % 10

            switch modulo {
            case 0: monitor.start(view: view, attributes: nil)
            case 1: monitor.stop(view: view, attributes: nil)
            case 2: monitor.add(viewError: ErrorMock(), source: .agent, attributes: nil)
            case 3: monitor.add(viewErrorMessage: .mockAny(), source: .agent, attributes: nil, stack: nil)
            case 4: monitor.start(resource: .mockAny(), url: .mockAny(), method: .mockAny(), attributes: nil)
            case 5: monitor.stop(resource: .mockAny(), kind: .mockAny(), httpStatusCode: 200, size: 0, attributes: nil)
            case 6: monitor.stop(resource: .mockAny(), withError: .mockAny(), errorSource: .agent, httpStatusCode: 400, attributes: nil)
            case 7: monitor.start(userAction: .scroll, attributes: nil)
            case 8: monitor.stop(userAction: .scroll, attributes: nil)
            case 9: monitor.add(userAction: .tap, attributes: nil)
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
        monitor.add(viewError: mockError, source: .agent, attributes: nil)
        monitor.add(viewErrorMessage: .mockAny(), source: .agent, attributes: nil, stack: nil)

        monitor.start(resource: .mockAny(), url: .mockAny(), method: .mockAny(), attributes: nil)
        monitor.stop(resource: .mockAny(), kind: .mockAny(), httpStatusCode: 200, size: 0, attributes: nil)
        monitor.stop(resource: .mockAny(), withError: .mockAny(), errorSource: .agent, httpStatusCode: 400, attributes: nil)

        monitor.start(userAction: .scroll, attributes: nil)
        monitor.stop(userAction: .scroll, attributes: nil)
        monitor.add(userAction: .tap, attributes: nil)

        let commands = scope.waitAndReturnProcessedCommands(count: 10, timeout: 0.5)

        XCTAssertTrue(commands[0] is RUMStartViewCommand)
        XCTAssertTrue(commands[1] is RUMStopViewCommand)
        XCTAssertTrue(commands[2] is RUMAddCurrentViewErrorCommand)
        XCTAssertTrue(commands[3] is RUMAddCurrentViewErrorCommand)
        XCTAssertTrue(commands[4] is RUMStartResourceCommand)
        XCTAssertTrue(commands[5] is RUMStopResourceCommand)
        XCTAssertTrue(commands[6] is RUMStopResourceWithErrorCommand)
        XCTAssertTrue(commands[7] is RUMStartUserActionCommand)
        XCTAssertTrue(commands[8] is RUMStopUserActionCommand)
        XCTAssertTrue(commands[9] is RUMAddUserActionCommand)
    }
}
