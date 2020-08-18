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
        let dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directory: temporaryDirectory,
            dependencies: .mockWith(
                dateProvider: dateProvider
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.startView(viewController: mockView)
        monitor.stopView(viewController: mockView)
        monitor.startView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        try rumEventMatchers[0].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
        }
        try rumEventMatchers[2].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.timeSpent, 1_000_000_000)
        }
        try rumEventMatchers[3].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 0)
        }
    }

    func testStartingView_thenLoadingResource() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directory: temporaryDirectory)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceName: "/resource/1", url: .mockAny(), httpMethod: .mockAny())
        monitor.stopResourceLoading(resourceName: "/resource/1", kind: .image, httpStatusCode: 200)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        try rumEventMatchers[0].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMResource.self) { rumModel in
            XCTAssertEqual(rumModel.resource.type, .image)
            XCTAssertEqual(rumModel.resource.statusCode, 200)
        }
        try rumEventMatchers[3].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 1)
        }
    }

    func testStartingView_thenTappingButton() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directory: temporaryDirectory,
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.startView(viewController: mockView)
        monitor.registerUserAction(type: .tap)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        try rumEventMatchers[0].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .tap)
        }
        try rumEventMatchers[3].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 2)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
    }

    func testStartingView_thenLoadingResources_whileScrolling() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directory: temporaryDirectory)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll)
        monitor.startResourceLoading(resourceName: "/resource/1", url: .mockAny(), httpMethod: .GET)
        monitor.stopResourceLoading(resourceName: "/resource/1", kind: .image, httpStatusCode: 200)
        monitor.startResourceLoading(resourceName: "/resource/2", url: .mockAny(), httpMethod: .GET)
        monitor.stopResourceLoading(resourceName: "/resource/2", kind: .image, httpStatusCode: 202)
        monitor.stopUserAction(type: .scroll)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 8)
        try rumEventMatchers[0].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMResource.self) { rumModel in
            XCTAssertEqual(rumModel.resource.statusCode, 200)
        }
        try rumEventMatchers[3].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 1)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
        try rumEventMatchers[4].model(ofType: RUMResource.self) { rumModel in
            XCTAssertEqual(rumModel.resource.statusCode, 202)
        }
        try rumEventMatchers[5].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 2)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
        try rumEventMatchers[6].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.resource?.count, 2)
            XCTAssertEqual(rumModel.action.error?.count, 0)
        }
        try rumEventMatchers[7].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 2)
            XCTAssertEqual(rumModel.view.resource.count, 2)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
    }

    func testStartingView_thenIssuingAnError_whileScrolling() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directory: temporaryDirectory,
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 0.01)
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: "abc-123")

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll)
        #sourceLocation(file: "/user/abc/Foo.swift", line: 100)
        monitor.addViewError(message: "View error message", source: .source)
        #sourceLocation()
        monitor.stopUserAction(type: .scroll)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 6)
        try rumEventMatchers[0].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMError.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "View error message")
            XCTAssertEqual(rumModel.error.stack, "Foo.swift: 100")
            XCTAssertEqual(rumModel.error.source, .source)
        }
        try rumEventMatchers[3].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
            XCTAssertEqual(rumModel.view.error.count, 1)
        }
        try rumEventMatchers[4].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .scroll)
            XCTAssertEqual(rumModel.action.error?.count, 1)
        }
        try rumEventMatchers[5].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 2)
            XCTAssertEqual(rumModel.view.resource.count, 0)
            XCTAssertEqual(rumModel.view.error.count, 1)
        }
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize(rumApplicationID: .mockAny())
        let view = mockView

        DispatchQueue.concurrentPerform(iterations: 900) { iteration in
            let modulo = iteration % 12

            switch modulo {
            case 0: monitor.startView(viewController: view)
            case 1: monitor.stopView(viewController: view)
            case 2: monitor.addViewError(error: ErrorMock(), source: .agent)
            case 3: monitor.addViewError(message: .mockAny(), source: .agent)
            case 4: monitor.startResourceLoading(resourceName: .mockAny(), url: .mockAny(), httpMethod: .mockAny())
            case 5: monitor.stopResourceLoading(resourceName: .mockAny(), kind: .mockAny(), httpStatusCode: .mockAny())
            case 6: monitor.stopResourceLoadingWithError(resourceName: .mockAny(), error: ErrorMock(), source: .network, httpStatusCode: .mockAny())
            case 7: monitor.stopResourceLoadingWithError(resourceName: .mockAny(), errorMessage: .mockAny(), source: .network)
            case 8: monitor.startUserAction(type: .scroll)
            case 9: monitor.stopUserAction(type: .scroll)
            case 10: monitor.registerUserAction(type: .tap)
            case 11: _ = monitor.contextProvider.context
            default: break
            }
        }
    }

    // MARK: - Initialization

    // TODO: RUMM-614 Change this test when final initialization API is provided
    func testWhenMonitorIsInitialized_itIsRegisteredAsGlobalMonitor() throws {
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance = nil }

        XCTAssertNil(RUMMonitor.shared)

        autoreleasepool {
            let monitor = RUMMonitor.initialize(rumApplicationID: .mockAny())
            XCTAssertNotNil(RUMMonitor.shared)
            _ = monitor
        }

        XCTAssertNil(RUMMonitor.shared)
    }
}
