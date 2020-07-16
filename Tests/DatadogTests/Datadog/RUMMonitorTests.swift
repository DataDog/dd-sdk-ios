/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import Datadog

class RUMMonitorTests: XCTestCase {
    func testWhenCallingPublicAPI_itProcessessExpectedCommandsThrougScopes() {
        let queue = DispatchQueue(label: #function)
        let scope = RUMScopeMock()

        let monitor = RUMMonitor(applicationScope: scope, queue: queue)

        let mockView = UIViewController()
        let mockAttributes = ["foo": "bar"]
        let mockError = ErrorMock()

        monitor.start(view: mockView, attributes: mockAttributes)
        monitor.stop(view: mockView, attributes: mockAttributes)
        monitor.addViewError(message: "error", error: mockError, attributes: mockAttributes)

        monitor.start(resource: "/resource/1", attributes: mockAttributes)
        monitor.stop(resource: "/resource/1", attributes: mockAttributes)
        monitor.stop(resource: "/resource/1", withError: ErrorMock(), attributes: mockAttributes)

        monitor.start(userAction: .scroll, attributes: mockAttributes)
        monitor.stop(userAction: .scroll, attributes: mockAttributes)
        monitor.add(userAction: .tap, attributes: mockAttributes)

        queue.sync {}

        XCTAssertEqual(
            scope.recordedCommands,
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
}
