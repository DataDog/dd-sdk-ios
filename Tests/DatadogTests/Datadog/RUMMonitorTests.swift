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

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.stopView(viewController: mockView)
        monitor.startView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        verifyGlobalAttributes(in: rumEventMatchers)
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

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceName: "/resource/1", url: .mockAny(), httpMethod: .mockAny())
        monitor.stopResourceLoading(resourceName: "/resource/1", kind: .image, httpStatusCode: 200)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        verifyGlobalAttributes(in: rumEventMatchers)
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

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        let actionName = String.mockRandom()
        monitor.startView(viewController: mockView)
        monitor.registerUserAction(type: .tap, name: actionName)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers[0].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .tap)
            XCTAssertEqual(rumModel.action.target?.name, actionName)
        }
        try rumEventMatchers[3].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 2)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
    }

    func testStartingView_thenLoadingResources_whileScrolling() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directory: temporaryDirectory)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll, name: .mockAny())
        monitor.startResourceLoading(resourceName: "/resource/1", url: .mockAny(), httpMethod: .GET)
        monitor.stopResourceLoading(resourceName: "/resource/1", kind: .image, httpStatusCode: 200)
        monitor.startResourceLoading(resourceName: "/resource/2", url: .mockAny(), httpMethod: .GET)
        monitor.stopResourceLoading(resourceName: "/resource/2", kind: .image, httpStatusCode: 202)
        monitor.stopUserAction(type: .scroll)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 8)
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers[0].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
        var userActionID: String?
        try rumEventMatchers[2].model(ofType: RUMResource.self) { rumModel in
            userActionID = rumModel.action?.id
            XCTAssertEqual(rumModel.resource.statusCode, 200)
        }
        XCTAssertNotNil(userActionID, "Resource should be associated with the User Action that issued its loading")
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
            XCTAssertEqual(rumModel.action.id, userActionID)
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

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll, name: .mockAny())
        #sourceLocation(file: "/user/abc/Foo.swift", line: 100)
        monitor.addViewError(message: "View error message", source: .source)
        #sourceLocation()
        monitor.stopUserAction(type: .scroll)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 6)
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers[0].model(ofType: RUMAction.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMView.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMError.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "View error message")
            XCTAssertEqual(rumModel.error.stack, "Foo.swift:100")
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

    func testStartingAnotherViewBeforeFirstIsStopped_thenLoadingResourcesAfterTapingButton() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directory: temporaryDirectory,
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(
                    startingFrom: Date(),
                    advancingBySeconds: RUMUserActionScope.Constants.discreteActionTimeoutDuration
                )
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        let view1 = createMockView(viewControllerClassName: "FirstViewController")
        monitor.startView(viewController: view1)
        let view2 = createMockView(viewControllerClassName: "SecondViewController")
        monitor.startView(viewController: view2)
        monitor.registerUserAction(type: .tap, name: .mockAny())
        monitor.startResourceLoading(resourceName: "/resource/1", url: .mockAny(), httpMethod: .mockAny())
        monitor.stopResourceLoading(resourceName: "/resource/1", kind: .mockAny(), httpStatusCode: .mockAny())
        monitor.stopView(viewController: view1)
        monitor.stopView(viewController: view2)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 9)
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMView.self) { rumModel in rumModel.view.url == "FirstViewController" }
            .model(ofType: RUMView.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "FirstViewController")
                XCTAssertEqual(rumModel.view.action.count, 1, "First View should track only the 'applicationStart' Action")
                XCTAssertEqual(rumModel.view.resource.count, 0)
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMView.self) { rumModel in rumModel.view.url == "SecondViewController" }
            .model(ofType: RUMView.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController")
                XCTAssertEqual(rumModel.view.action.count, 1, "Second View should track the 'tap' Action")
                XCTAssertEqual(rumModel.view.resource.count, 1, "Second View should track the Resource")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMAction.self)
            .model(ofType: RUMAction.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController", "Action should be associated with the second View")
                XCTAssertEqual(rumModel.action.type, .tap)
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMResource.self)
            .model(ofType: RUMResource.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController", "Resource should be associated with the second View")
            }
    }

    func testStartingLoadingResourcesFromTheFirstView_thenStartingAnotherViewWhichAlsoLoadsResources() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directory: temporaryDirectory)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        let view1 = createMockView(viewControllerClassName: "FirstViewController")
        monitor.startView(viewController: view1)
        monitor.startResourceLoading(resourceName: "/resource/1", url: .mockWith(pathComponent: "/resource/1"), httpMethod: .mockAny())
        monitor.startResourceLoading(resourceName: "/resource/2", url: .mockWith(pathComponent: "/resource/2"), httpMethod: .mockAny())
        monitor.stopView(viewController: view1)

        let view2 = createMockView(viewControllerClassName: "SecondViewController")
        monitor.startView(viewController: view2)
        monitor.startResourceLoading(resourceName: "/resource/3", url: .mockWith(pathComponent: "/resource/3"), httpMethod: .mockAny())
        monitor.startResourceLoading(resourceName: "/resource/4", url: .mockWith(pathComponent: "/resource/4"), httpMethod: .mockAny())
        monitor.stopResourceLoading(resourceName: "/resource/1", kind: .mockAny(), httpStatusCode: .mockAny())
        monitor.stopResourceLoadingWithError(resourceName: "/resource/2", errorMessage: .mockAny(), source: .network)
        monitor.stopResourceLoading(resourceName: "/resource/3", kind: .mockAny(), httpStatusCode: .mockAny())
        monitor.stopResourceLoading(resourceName: "/resource/4", kind: .mockAny(), httpStatusCode: .mockAny())
        monitor.stopView(viewController: view2)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 13)
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMView.self) { rumModel in rumModel.view.url == "FirstViewController" }
            .model(ofType: RUMView.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "FirstViewController")
                XCTAssertEqual(rumModel.view.resource.count, 1, "First View should track 1 Resource")
                XCTAssertEqual(rumModel.view.error.count, 1, "First View should track 1 Resource Error")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMView.self) { rumModel in rumModel.view.url == "SecondViewController" }
            .model(ofType: RUMView.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController")
                XCTAssertEqual(rumModel.view.resource.count, 2, "Second View should track 2 Resources")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMResource.self) { rumModel in rumModel.resource.url.contains("/resource/1") }
            .model(ofType: RUMResource.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "FirstViewController", "Resource should be associated with the first View")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMError.self) { rumModel in rumModel.error.resource?.url.contains("/resource/2") ?? false }
            .model(ofType: RUMError.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "FirstViewController", "Resource should be associated with the first View")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMResource.self) { rumModel in rumModel.resource.url.contains("/resource/3") }
            .model(ofType: RUMResource.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController", "Resource should be associated with the second View")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMResource.self) { rumModel in rumModel.resource.url.contains("/resource/4") }
            .model(ofType: RUMResource.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController", "Resource should be associated with the second View")
            }
    }

    func testStartingView_thenTappingButton_thenTappingAnotherButton() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directory: temporaryDirectory,
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()

        monitor.startView(viewController: mockView)
        monitor.registerUserAction(type: .tap, name: "1st action")
        monitor.registerUserAction(type: .swipe, name: "2nd action")
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        try rumEventMatchers.lastRUMEvent(ofType: RUMAction.self) { $0.action.target?.name == "1st action" }
            .model(ofType: RUMAction.self) { rumModel in
                XCTAssertEqual(rumModel.action.type, .tap)
            }
        try rumEventMatchers.lastRUMEvent(ofType: RUMAction.self) { $0.action.target?.name == "2nd action" }
            .model(ofType: RUMAction.self) { rumModel in
                XCTAssertEqual(rumModel.action.type, .swipe)
            }
        try rumEventMatchers.lastRUMEvent(ofType: RUMView.self)
            .model(ofType: RUMView.self) { rumModel in
                XCTAssertEqual(rumModel.view.action.count, 3)
            }
    }

    // MARK: - Sending user info

    func testWhenUserInfoIsProvided_itIsSendWithAllEvents() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directory: temporaryDirectory,
            dependencies: .mockWith(
                userInfoProvider: .mockWith(
                    userInfo: UserInfo(id: "abc-123", name: "Foo", email: "foo@bar.com")
                )
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll, name: .mockAny())
        monitor.startResourceLoading(resourceName: "/resource/1", url: .mockWith(pathComponent: "/resource/1"), httpMethod: .mockAny())
        monitor.startResourceLoading(resourceName: "/resource/2", url: .mockWith(pathComponent: "/resource/2"), httpMethod: .mockAny())
        monitor.stopUserAction(type: .scroll)
        monitor.stopResourceLoading(resourceName: "/resource/1", kind: .mockAny(), httpStatusCode: .mockAny())
        monitor.stopResourceLoadingWithError(resourceName: "/resource/2", errorMessage: .mockAny(), source: .network)
        monitor.addViewError(message: .mockAny(), source: .source)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 11)
        let expectedUserInfo = RUMUSR(id: "abc-123", name: "Foo", email: "foo@bar.com")
        try rumEventMatchers.forEachRUMEvent(ofType: RUMAction.self) { action in
            XCTAssertEqual(action.usr, expectedUserInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMView.self) { view in
            XCTAssertEqual(view.usr, expectedUserInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMResource.self) { resource in
            XCTAssertEqual(resource.usr, expectedUserInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMError.self) { error in
            XCTAssertEqual(error.usr, expectedUserInfo)
        }
    }

    // MARK: - Sending connectivity info

    func testWhenNetworkAndCarrierInfoAreProvided_thenConnectivityInfoIsSendWithAllEvents() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directory: temporaryDirectory,
            dependencies: .mockWith(
                networkConnectionInfoProvider: NetworkConnectionInfoProviderMock(
                    networkConnectionInfo: .mockWith(reachability: .yes, availableInterfaces: [.cellular])
                ),
                carrierInfoProvider: CarrierInfoProviderMock(
                    carrierInfo: .mockWith(carrierName: "Carrier Name", radioAccessTechnology: .GPRS)
                )
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll, name: .mockAny())
        monitor.startResourceLoading(resourceName: "/resource/1", url: .mockWith(pathComponent: "/resource/1"), httpMethod: .mockAny())
        monitor.startResourceLoading(resourceName: "/resource/2", url: .mockWith(pathComponent: "/resource/2"), httpMethod: .mockAny())
        monitor.stopUserAction(type: .scroll)
        monitor.stopResourceLoading(resourceName: "/resource/1", kind: .mockAny(), httpStatusCode: .mockAny())
        monitor.stopResourceLoadingWithError(resourceName: "/resource/2", errorMessage: .mockAny(), source: .network)
        monitor.addViewError(message: .mockAny(), source: .source)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 11)
        let expectedConnectivityInfo = RUMConnectivity(
            status: .connected,
            interfaces: [.cellular],
            cellular: RUMCellular(technology: "GPRS", carrierName: "Carrier Name")
        )
        try rumEventMatchers.forEachRUMEvent(ofType: RUMAction.self) { action in
            XCTAssertEqual(action.connectivity, expectedConnectivityInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMView.self) { view in
            XCTAssertEqual(view.connectivity, expectedConnectivityInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMResource.self) { resource in
            XCTAssertEqual(resource.connectivity, expectedConnectivityInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMError.self) { error in
            XCTAssertEqual(error.connectivity, expectedConnectivityInfo)
        }
    }

    // MARK: - Sending Attributes

    func testSendingAttributes() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directory: temporaryDirectory)
        defer { RUMFeature.instance = nil }

        let view1 = createMockView(viewControllerClassName: "FirstViewController")
        let view2 = createMockView(viewControllerClassName: "SecondViewController")

        let monitor = RUMMonitor.initialize()

        // set global attributes:
        monitor.addAttribute(forKey: "attribute1", value: "value 1")
        monitor.addAttribute(forKey: "attribute2", value: "value 2")

        // start View 1:
        monitor.startView(viewController: view1)

        // update global attributes while the View 1 is active
        monitor.addAttribute(forKey: "attribute1", value: "changed value 1") // change the attribute value
        monitor.removeAttribute(forKey: "attribute2") // remove the attribute

        monitor.stopView(viewController: view1)

        // start View 2:
        monitor.startView(viewController: view2)
        monitor.stopView(viewController: view2)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 3)
        let firstViewEvent = try rumEventMatchers
            .lastRUMEvent(ofType: RUMView.self) { rumModel in rumModel.view.url == "FirstViewController" }

        XCTAssertEqual(try firstViewEvent.attribute(forKeyPath: "attribute1") as String, "changed value 1")
        XCTAssertEqual(try firstViewEvent.attribute(forKeyPath: "attribute2") as String, "value 2")

        let secondViewEvent = try rumEventMatchers
            .lastRUMEvent(ofType: RUMView.self) { rumModel in rumModel.view.url == "SecondViewController" }

        XCTAssertEqual(try secondViewEvent.attribute(forKeyPath: "attribute1") as String, "changed value 1")
        XCTAssertNil(try? secondViewEvent.attribute(forKeyPath: "attribute2") as String)
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        let view = mockView

        DispatchQueue.concurrentPerform(iterations: 900) { iteration in
            let modulo = iteration % 15

            switch modulo {
            case 0: monitor.startView(viewController: view)
            case 1: monitor.stopView(viewController: view)
            case 2: monitor.addViewError(error: ErrorMock(), source: .agent)
            case 3: monitor.addViewError(message: .mockAny(), source: .agent)
            case 4: monitor.startResourceLoading(resourceName: .mockAny(), url: .mockAny(), httpMethod: .mockAny())
            case 5: monitor.stopResourceLoading(resourceName: .mockAny(), kind: .mockAny(), httpStatusCode: .mockAny())
            case 6: monitor.stopResourceLoadingWithError(resourceName: .mockAny(), error: ErrorMock(), source: .network, httpStatusCode: .mockAny())
            case 7: monitor.stopResourceLoadingWithError(resourceName: .mockAny(), errorMessage: .mockAny(), source: .network)
            case 8: monitor.startUserAction(type: .scroll, name: .mockRandom())
            case 9: monitor.stopUserAction(type: .scroll)
            case 10: monitor.registerUserAction(type: .tap, name: .mockRandom())
            case 11: _ = monitor.dd.contextProvider.context
            case 12: monitor.addAttribute(forKey: String.mockRandom(), value: String.mockRandom())
            case 13: monitor.removeAttribute(forKey: String.mockRandom())
            case 14: monitor.dd.enableRUMDebugging(.random())
            default: break
            }
        }
    }

    // MARK: - Usage

    func testGivenDatadogNotInitialized_whenInitializingRUMMonitor_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        XCTAssertNil(Datadog.instance)

        // when
        let monitor = RUMMonitor.initialize()

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `RUMMonitor.initialize()`."
        )
        XCTAssertTrue(monitor is DDNoopRUMMonitor)
    }

    func testGivenRUMFeatureDisabled_whenInitializingRUMMonitor_itPrintsError() throws {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        Datadog.initialize(
            appContext: .mockAny(),
            configuration: Datadog.Configuration.builderUsing(clientToken: "abc-def", environment: "tests").build()
        )

        // when
        let monitor = RUMMonitor.initialize()

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `RUMMonitor.initialize()` produces a non-functional monitor, as the RUM feature is disabled."
        )
        XCTAssertTrue(monitor is DDNoopRUMMonitor)

        try Datadog.deinitializeOrThrow()
    }

    func testGivenRUMMonitorInitialized_whenInitializingAnotherTime_itPrintsError() throws {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        Datadog.initialize(
            appContext: .mockAny(),
            configuration: Datadog.Configuration.builderUsing(rumApplicationID: .mockAny(), clientToken: .mockAny(), environment: .mockAny()).build()
        )
        Global.rum = RUMMonitor.initialize()
        defer { Global.rum = DDNoopRUMMonitor() }

        // when
        _ = RUMMonitor.initialize()

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            """
            🔥 Datadog SDK usage error: The `RUMMonitor` instance was already created. Use existing `Global.rum` instead of initializing the `RUMMonitor` another time.
            """
        )

        try Datadog.deinitializeOrThrow()
    }

    func testGivenRUMMonitorInitialized_whenTogglingDatadogDebugRUM_itTogglesRUMDebugging() throws {
        // given
        Datadog.initialize(
            appContext: .mockAny(),
            configuration: .mockWith(rumApplicationID: "rum-123", rumEnabled: true)
        )
        Global.rum = RUMMonitor.initialize()
        defer { Global.rum = DDNoopRUMMonitor() }

        let monitor = Global.rum.dd
        monitor.queue.sync {
            XCTAssertNil(monitor.debugging)
        }

        // when & then
        Datadog.debugRUM = true
        monitor.queue.sync {
            XCTAssertNotNil(monitor.debugging)
        }

        Datadog.debugRUM = false
        monitor.queue.sync {
            XCTAssertNil(monitor.debugging)
        }

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Private helpers

    private var expectedAttributes = [String: String]()
    private func setGlobalAttributes(of monitor: DDRUMMonitor) {
        expectedAttributes = [String.mockRandom(): String.mockRandom()]
        expectedAttributes.forEach {
            monitor.addAttribute(forKey: $0, value: $1)
        }
    }

    private func verifyGlobalAttributes(in matchers: [RUMEventMatcher]) {
        for matcher in matchers {
            expectedAttributes.forEach { attrKey, attrValue in
                XCTAssertEqual(try? matcher.attribute(forKeyPath: attrKey), attrValue)
            }
        }
    }
}
