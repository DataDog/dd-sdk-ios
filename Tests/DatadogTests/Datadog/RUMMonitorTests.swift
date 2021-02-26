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
        temporaryFeatureDirectories.create()
    }

    override func tearDown() {
        XCTAssertNil(Datadog.instance)
        XCTAssertNil(RUMFeature.instance)
        temporaryFeatureDirectories.delete()
        super.tearDown()
    }

    // MARK: - Sending RUM events

    func testStartingViewIdentifiedByViewController() throws {
        let dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
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
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
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

    func testStartingViewIdentifiedByStringKey() throws {
        let dateProvider = RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                dateProvider: dateProvider
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        monitor.startView(key: "view1", name: "View1")
        monitor.stopView(key: "view1")
        monitor.startView(key: "view2", name: "View2")

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        XCTAssertEqual(session.viewVisits.count, 2)
        XCTAssertEqual(session.viewVisits[0].name, "View1")
        XCTAssertEqual(session.viewVisits[0].path, "View1")
        XCTAssertEqual(session.viewVisits[1].name, "View2")
        XCTAssertEqual(session.viewVisits[1].path, "View2")
    }

    func testStartingView_thenLoadingImageResourceWithRequest() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directories: temporaryFeatureDirectories)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockWith(httpMethod: "GET"))
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockWith(statusCode: 200, mimeType: "image/png"))

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMResourceEvent.self) { rumModel in
            XCTAssertEqual(rumModel.resource.type, .image)
            XCTAssertEqual(rumModel.resource.statusCode, 200)
        }
        try rumEventMatchers[3].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 1)
        }
    }

    func testStartingView_thenLoadingXHRResourceWithRequestWithMetrics() throws {
        guard #available(iOS 13, *) else {
            return // `URLSessionTaskMetrics` mocking doesn't work prior to iOS 13.0
        }

        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directories: temporaryFeatureDirectories)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockWith(httpMethod: "POST"))
        monitor.addResourceMetrics(
            resourceKey: "/resource/1",
            metrics: .mockWith(
                taskInterval: DateInterval(start: .mockDecember15th2019At10AMUTC(), duration: 4),
                transactionMetrics: [
                    .mockWith(
                        domainLookupStartDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 1),
                        domainLookupEndDate: .mockDecember15th2019At10AMUTC(addingTimeInterval: 3)
                    )
                ]
            )
        )
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockWith(statusCode: 200, mimeType: "image/png"))

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let resourceEvent = session.viewVisits[0].resourceEvents[0]
        XCTAssertEqual(resourceEvent.resource.type, .xhr, "POST Resources should always have the `.xhr` kind")
        XCTAssertEqual(resourceEvent.resource.statusCode, 200)
        XCTAssertEqual(resourceEvent.resource.duration, 4_000_000_000)
        XCTAssertEqual(resourceEvent.resource.dns!.start, 1_000_000_000)
        XCTAssertEqual(resourceEvent.resource.dns!.duration, 2_000_000_000)
    }

    func testStartingView_thenLoadingResourceWithURL() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directories: temporaryFeatureDirectories)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        let url: URL = .mockRandom()
        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceKey: "/resource/1", url: url)
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockWith(statusCode: 200, mimeType: "image/png"))

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let resourceEvent = session.viewVisits[0].resourceEvents[0]
        XCTAssertEqual(resourceEvent.resource.url, url.absoluteString)
        XCTAssertEqual(resourceEvent.resource.statusCode, 200)
    }

    func testStartingView_thenLoadingResourceWithURLString() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directories: temporaryFeatureDirectories)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceKey: "/resource/1", httpMethod: .post, urlString: "/some/url/string", attributes: [:])
        monitor.stopResourceLoading(resourceKey: "/resource/1", statusCode: 333, kind: .beacon)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let resourceEvent = session.viewVisits[0].resourceEvents[0]
        XCTAssertEqual(resourceEvent.resource.url, "/some/url/string")
        XCTAssertEqual(resourceEvent.resource.statusCode, 333)
        XCTAssertEqual(resourceEvent.resource.type, .beacon)
        XCTAssertEqual(resourceEvent.resource.method, .post)
    }

    func testStartingView_thenTappingButton() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        let actionName = String.mockRandom()
        monitor.startView(viewController: mockView)
        monitor.addUserAction(type: .tap, name: actionName)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .tap)
            XCTAssertEqual(rumModel.action.target?.name, actionName)
        }
        try rumEventMatchers[3].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 2)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
    }

    func testStartingView_thenLoadingResources_whileScrolling() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directories: temporaryFeatureDirectories)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll, name: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockWith(httpMethod: "GET"))
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockWith(statusCode: 200))
        monitor.startResourceLoading(resourceKey: "/resource/2", request: .mockWith(httpMethod: "POST"))
        monitor.stopResourceLoading(resourceKey: "/resource/2", response: .mockWith(statusCode: 202))
        monitor.stopUserAction(type: .scroll)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 8)
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
        var userActionID: String?
        try rumEventMatchers[2].model(ofType: RUMResourceEvent.self) { rumModel in
            userActionID = rumModel.action?.id
            XCTAssertEqual(rumModel.resource.statusCode, 200)
            XCTAssertEqual(rumModel.resource.method, .get)
        }
        XCTAssertNotNil(userActionID, "Resource should be associated with the User Action that issued its loading")
        try rumEventMatchers[3].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 1)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
        try rumEventMatchers[4].model(ofType: RUMResourceEvent.self) { rumModel in
            XCTAssertEqual(rumModel.resource.statusCode, 202)
            XCTAssertEqual(rumModel.resource.method, .post)
        }
        try rumEventMatchers[5].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 2)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
        try rumEventMatchers[6].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.resource?.count, 2)
            XCTAssertEqual(rumModel.action.error?.count, 0)
            XCTAssertEqual(rumModel.action.id, userActionID)
        }
        try rumEventMatchers[7].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 2)
            XCTAssertEqual(rumModel.view.resource.count, 2)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
    }

    func testStartingView_thenIssuingAnError_whileScrolling() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
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
        monitor.addError(message: "View error message", source: .source)
        #sourceLocation()
        monitor.addError(message: "Another error message", source: .webview, stack: "Error stack")
        monitor.stopUserAction(type: .scroll)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 8)
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        try rumEventMatchers[1].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[2].model(ofType: RUMErrorEvent.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "View error message")
            XCTAssertEqual(rumModel.error.stack, "Foo.swift:100")
            XCTAssertEqual(rumModel.error.source, .source)
            XCTAssertNil(rumModel.error.type)
        }
        try rumEventMatchers[3].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
            XCTAssertEqual(rumModel.view.error.count, 1)
        }
        try rumEventMatchers[4].model(ofType: RUMErrorEvent.self) { rumModel in
            XCTAssertEqual(rumModel.error.message, "Another error message")
            XCTAssertEqual(rumModel.error.stack, "Error stack")
            XCTAssertEqual(rumModel.error.source, .webview)
            XCTAssertNil(rumModel.error.type)
        }
        try rumEventMatchers[5].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
            XCTAssertEqual(rumModel.view.error.count, 2)
        }
        try rumEventMatchers[6].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .scroll)
            XCTAssertEqual(rumModel.action.error?.count, 2)
        }
        try rumEventMatchers[7].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 2)
            XCTAssertEqual(rumModel.view.resource.count, 0)
            XCTAssertEqual(rumModel.view.error.count, 2)
        }
    }

    func testStartingAnotherViewBeforeFirstIsStopped_thenLoadingResourcesAfterTapingButton() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
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
        monitor.addUserAction(type: .tap, name: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockAny())
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.stopView(viewController: view1)
        monitor.stopView(viewController: view2)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 9)
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMViewEvent.self) { rumModel in rumModel.view.url == "FirstViewController" }
            .model(ofType: RUMViewEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "FirstViewController")
                XCTAssertEqual(rumModel.view.name, "FirstViewController")
                XCTAssertEqual(rumModel.view.action.count, 1, "First View should track only the 'applicationStart' Action")
                XCTAssertEqual(rumModel.view.resource.count, 0)
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMViewEvent.self) { rumModel in rumModel.view.url == "SecondViewController" }
            .model(ofType: RUMViewEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController")
                XCTAssertEqual(rumModel.view.name, "SecondViewController")
                XCTAssertEqual(rumModel.view.action.count, 1, "Second View should track the 'tap' Action")
                XCTAssertEqual(rumModel.view.resource.count, 1, "Second View should track the Resource")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMActionEvent.self)
            .model(ofType: RUMActionEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController", "Action should be associated with the second View")
                XCTAssertEqual(rumModel.view.name, "SecondViewController", "Action should be associated with the second View")
                XCTAssertEqual(rumModel.action.type, .tap)
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMResourceEvent.self)
            .model(ofType: RUMResourceEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController", "Resource should be associated with the second View")
                XCTAssertEqual(rumModel.view.name, "SecondViewController", "Resource should be associated with the second View")
            }
    }

    func testStartingLoadingResourcesFromTheFirstView_thenStartingAnotherViewWhichAlsoLoadsResources() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directories: temporaryFeatureDirectories)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        let view1 = createMockView(viewControllerClassName: "FirstViewController")
        monitor.startView(viewController: view1)
        monitor.startResourceLoading(resourceKey: "/resource/1", request: URLRequest(url: .mockWith(pathComponent: "/resource/1")))
        monitor.startResourceLoading(resourceKey: "/resource/2", request: URLRequest(url: .mockWith(pathComponent: "/resource/2")))

        monitor.stopView(viewController: view1)

        let view2 = createMockView(viewControllerClassName: "SecondViewController")
        monitor.startView(viewController: view2)
        monitor.startResourceLoading(resourceKey: "/resource/3", request: URLRequest(url: .mockWith(pathComponent: "/resource/3")))
        monitor.startResourceLoading(resourceKey: "/resource/4", request: URLRequest(url: .mockWith(pathComponent: "/resource/4")))
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.stopResourceLoadingWithError(resourceKey: "/resource/2", errorMessage: .mockAny())
        monitor.stopResourceLoading(resourceKey: "/resource/3", response: .mockAny())
        monitor.stopResourceLoading(resourceKey: "/resource/4", response: .mockAny())
        monitor.stopView(viewController: view2)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 13)
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMViewEvent.self) { rumModel in rumModel.view.url == "FirstViewController" }
            .model(ofType: RUMViewEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "FirstViewController")
                XCTAssertEqual(rumModel.view.name, "FirstViewController")
                XCTAssertEqual(rumModel.view.resource.count, 1, "First View should track 1 Resource")
                XCTAssertEqual(rumModel.view.error.count, 1, "First View should track 1 Resource Error")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMViewEvent.self) { rumModel in rumModel.view.url == "SecondViewController" }
            .model(ofType: RUMViewEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController")
                XCTAssertEqual(rumModel.view.name, "SecondViewController")
                XCTAssertEqual(rumModel.view.resource.count, 2, "Second View should track 2 Resources")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMResourceEvent.self) { rumModel in rumModel.resource.url.contains("/resource/1") }
            .model(ofType: RUMResourceEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "FirstViewController", "Resource should be associated with the first View")
                XCTAssertEqual(rumModel.view.name, "FirstViewController", "Resource should be associated with the first View")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMErrorEvent.self) { rumModel in rumModel.error.resource?.url.contains("/resource/2") ?? false }
            .model(ofType: RUMErrorEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "FirstViewController", "Resource should be associated with the first View")
                XCTAssertEqual(rumModel.view.name, "FirstViewController", "Resource should be associated with the first View")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMResourceEvent.self) { rumModel in rumModel.resource.url.contains("/resource/3") }
            .model(ofType: RUMResourceEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController", "Resource should be associated with the second View")
                XCTAssertEqual(rumModel.view.name, "SecondViewController", "Resource should be associated with the second View")
            }
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMResourceEvent.self) { rumModel in rumModel.resource.url.contains("/resource/4") }
            .model(ofType: RUMResourceEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "SecondViewController", "Resource should be associated with the second View")
                XCTAssertEqual(rumModel.view.name, "SecondViewController", "Resource should be associated with the second View")
            }
    }

    func testStartingView_thenTappingButton_thenTappingAnotherButton() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()

        monitor.startView(viewController: mockView)
        monitor.addUserAction(type: .tap, name: "1st action")
        monitor.addUserAction(type: .swipe, name: "2nd action")
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        try rumEventMatchers.lastRUMEvent(ofType: RUMActionEvent.self) { $0.action.target?.name == "1st action" }
            .model(ofType: RUMActionEvent.self) { rumModel in
                XCTAssertEqual(rumModel.action.type, .tap)
            }
        try rumEventMatchers.lastRUMEvent(ofType: RUMActionEvent.self) { $0.action.target?.name == "2nd action" }
            .model(ofType: RUMActionEvent.self) { rumModel in
                XCTAssertEqual(rumModel.action.type, .swipe)
            }
        try rumEventMatchers.lastRUMEvent(ofType: RUMViewEvent.self)
            .model(ofType: RUMViewEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.action.count, 3)
            }
    }

    // MARK: - Sending user info

    func testWhenUserInfoIsProvided_itIsSendWithAllEvents() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                userInfoProvider: .mockWith(
                    userInfo: UserInfo(
                        id: "abc-123",
                        name: "Foo",
                        email: "foo@bar.com",
                        extraInfo: [
                            "str": "value",
                            "int": 11_235,
                            "bool": true
                        ]
                    )
                )
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll, name: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/2", request: .mockAny())
        monitor.stopUserAction(type: .scroll)
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.stopResourceLoadingWithError(resourceKey: "/resource/2", errorMessage: .mockAny())
        monitor.addError(message: .mockAny(), source: .source)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 11)
        let expectedUserInfo = RUMUser(email: "foo@bar.com", id: "abc-123", name: "Foo")
        try rumEventMatchers.forEach { event in
            XCTAssertEqual(try event.attribute(forKeyPath: "context.usr.str"), "value")
            XCTAssertEqual(try event.attribute(forKeyPath: "context.usr.int"), 11_235)
            XCTAssertEqual(try event.attribute(forKeyPath: "context.usr.bool"), true) // swiftlint:disable:this xct_specific_matcher
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMActionEvent.self) { action in
            XCTAssertEqual(action.usr, expectedUserInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMViewEvent.self) { view in
            XCTAssertEqual(view.usr, expectedUserInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMResourceEvent.self) { resource in
            XCTAssertEqual(resource.usr, expectedUserInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMErrorEvent.self) { error in
            XCTAssertEqual(error.usr, expectedUserInfo)
        }
    }

    // MARK: - Sending connectivity info

    func testWhenNetworkAndCarrierInfoAreProvided_thenConnectivityInfoIsSendWithAllEvents() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
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
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/2", request: .mockAny())
        monitor.stopUserAction(type: .scroll)
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.stopResourceLoadingWithError(resourceKey: "/resource/2", errorMessage: .mockAny())
        monitor.addError(message: .mockAny(), source: .source)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 11)
        let expectedConnectivityInfo = RUMConnectivity(
            cellular: RUMConnectivity.Cellular(carrierName: "Carrier Name", technology: "GPRS"),
            interfaces: [.cellular],
            status: .connected
        )
        try rumEventMatchers.forEachRUMEvent(ofType: RUMActionEvent.self) { action in
            XCTAssertEqual(action.connectivity, expectedConnectivityInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMViewEvent.self) { view in
            XCTAssertEqual(view.connectivity, expectedConnectivityInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMResourceEvent.self) { resource in
            XCTAssertEqual(resource.connectivity, expectedConnectivityInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMErrorEvent.self) { error in
            XCTAssertEqual(error.connectivity, expectedConnectivityInfo)
        }
    }

    // MARK: - Sending Attributes

    func testSendingAttributes() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directories: temporaryFeatureDirectories)
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
            .lastRUMEvent(ofType: RUMViewEvent.self) { rumModel in rumModel.view.url == "FirstViewController" }

        XCTAssertNil(try? firstViewEvent.attribute(forKeyPath: "attribute1") as String)
        XCTAssertNil(try? firstViewEvent.attribute(forKeyPath: "attribute2") as String)
        XCTAssertEqual(try firstViewEvent.attribute(forKeyPath: "context.attribute1") as String, "changed value 1")
        XCTAssertEqual(try firstViewEvent.attribute(forKeyPath: "context.attribute2") as String, "value 2")

        let secondViewEvent = try rumEventMatchers
            .lastRUMEvent(ofType: RUMViewEvent.self) { rumModel in rumModel.view.url == "SecondViewController" }

        XCTAssertNil(try? secondViewEvent.attribute(forKeyPath: "attribute1") as String)
        XCTAssertEqual(try secondViewEvent.attribute(forKeyPath: "context.attribute1") as String, "changed value 1")
        XCTAssertNil(try? secondViewEvent.attribute(forKeyPath: "context.attribute2") as String)
    }

    func testWhenViewIsStarted_attributesCanBeAddedOrUpdatedButNotRemoved() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(directories: temporaryFeatureDirectories)
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()

        monitor.addAttribute(forKey: "a1", value: "foo1")
        monitor.addAttribute(forKey: "a2", value: "foo2")

        monitor.startView(viewController: mockView)

        monitor.addAttribute(forKey: "a1", value: "bar1") // update
        monitor.removeAttribute(forKey: "a2") // remove
        monitor.addAttribute(forKey: "a3", value: "foo3") // add

        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 3)
        let lastViewUpdate = try rumEventMatchers.lastRUMEvent(ofType: RUMViewEvent.self)

        XCTAssertNil(try? lastViewUpdate.attribute(forKeyPath: "a1") as String)
        XCTAssertNil(try? lastViewUpdate.attribute(forKeyPath: "a2") as String)
        XCTAssertNil(try? lastViewUpdate.attribute(forKeyPath: "a3") as String)
        try XCTAssertEqual(lastViewUpdate.attribute(forKeyPath: "context.a1"), "bar1", "The value should be updated")
        try XCTAssertEqual(lastViewUpdate.attribute(forKeyPath: "context.a2"), "foo2", "The attribute should not be removed")
        try XCTAssertEqual(lastViewUpdate.attribute(forKeyPath: "context.a3"), "foo3", "The attribute should be added")
    }

    // MARK: - Sending Custom Timings

    func testStartingView_thenAddingTiming() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(
                    startingFrom: Date(),
                    advancingBySeconds: 1
                )
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.addTiming(name: "timing1")
        monitor.addTiming(name: "timing2")

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 4)
        verifyGlobalAttributes(in: rumEventMatchers)
        let lastViewUpdate = try rumEventMatchers.lastRUMEvent(ofType: RUMViewEvent.self)
        XCTAssertEqual(try lastViewUpdate.timing(named: "timing1"), 1_000_000_000)
        XCTAssertEqual(try lastViewUpdate.timing(named: "timing2"), 2_000_000_000)
    }

    // MARK: - RUM Events Dates Correction

    func testGivenTimeDifferenceBetweenDeviceAndServer_whenCollectingRUMEvents_thenEventsDateUseServerTime() throws {
        // Given
        let deviceTime: Date = .mockDecember15th2019At10AMUTC()
        var serverTimeDifference = TimeInterval.random(in: 600..<1_200).rounded() // 10 - 20 minutes difference
        serverTimeDifference = serverTimeDifference * (Bool.random() ? 1 : -1) // positive or negative difference
        let dateProvider = RelativeDateProvider(
            startingFrom: deviceTime,
            advancingBySeconds: 1 // short advancing, so all events will be collected less than a minute after `deviceTime`
        )

        // When
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                dateProvider: dateProvider,
                dateCorrector: DateCorrectorMock(correctionOffset: serverTimeDifference)
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()

        monitor.startView(viewController: mockView)
        monitor.addUserAction(type: .tap, name: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockAny())
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/2", url: .mockAny())
        monitor.stopResourceLoadingWithError(resourceKey: "/resource/2", errorMessage: .mockAny())
        monitor.addError(message: .mockAny())

        // Then
        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 10)
        let session = try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers)[0]

        let viewEvents = session.viewVisits[0].viewEvents
        let actionEvents = session.viewVisits[0].actionEvents
        let resourceEvents = session.viewVisits[0].resourceEvents
        let errorEvents = session.viewVisits[0].errorEvents

        XCTAssertGreaterThan(viewEvents.count, 0)
        XCTAssertGreaterThan(actionEvents.count, 0)
        XCTAssertGreaterThan(resourceEvents.count, 0)
        XCTAssertGreaterThan(errorEvents.count, 0)

        // All RUM events should be send later than or equal this earliest server time
        let earliestServerTime = deviceTime.addingTimeInterval(serverTimeDifference).timeIntervalSince1970.toInt64Milliseconds

        viewEvents.forEach { view in
            XCTAssertGreaterThanOrEqual(view.date, earliestServerTime, "Event `date` should be adjusted to server time")
        }
        actionEvents.forEach { action in
            XCTAssertGreaterThanOrEqual(action.date, earliestServerTime, "Event `date` should be adjusted to server time")
        }
        resourceEvents.forEach { resource in
            XCTAssertGreaterThanOrEqual(resource.date, earliestServerTime, "Event `date` should be adjusted to server time")
        }
        errorEvents.forEach { error in
            XCTAssertGreaterThanOrEqual(error.date, earliestServerTime, "Event `date` should be adjusted to server time")
        }
    }

    // MARK: - Tracking Consent

    func testWhenChangingConsentValues_itUploadsOnlyAuthorizedRUMEvents() throws {
        let consentProvider = ConsentProvider(initialConsent: .pending)

        // Given
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
            dependencies: .mockWith(
                consentProvider: consentProvider,
                dateProvider: RelativeDateProvider(
                    startingFrom: Date(),
                    advancingBySeconds: 1
                )
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()

        // When
        monitor.startView(viewController: mockView, name: "view in `.pending` consent changed to `.granted`")
        monitor.stopView(viewController: mockView)
        monitor.dd.queue.sync {} // wait for processing the event in `RUMMonitor`
        consentProvider.changeConsent(to: .granted)
        monitor.startView(viewController: mockView, name: "view in `.granted` consent")
        monitor.stopView(viewController: mockView)
        monitor.dd.queue.sync {}
        consentProvider.changeConsent(to: .notGranted)
        monitor.startView(viewController: mockView, name: "view in `.notGranted` consent")
        monitor.stopView(viewController: mockView)
        monitor.dd.queue.sync {}
        consentProvider.changeConsent(to: .granted)
        monitor.startView(viewController: mockView, name: "another view in `.granted` consent")
        monitor.stopView(viewController: mockView)

        // Then
        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 7)
        let session = try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers)[0]

        XCTAssertEqual(session.viewVisits.count, 3, "Only 3 RUM Views were visited in authorized consent.")
        XCTAssertEqual(session.viewVisits[0].name, "view in `.pending` consent changed to `.granted`")
        XCTAssertEqual(session.viewVisits[1].name, "view in `.granted` consent")
        XCTAssertEqual(session.viewVisits[2].name, "another view in `.granted` consent")
    }

    // MARK: - Data Scrubbing

    func testModifyingEventsBeforeTheyGetSend() throws {
        RUMFeature.instance = .mockByRecordingRUMEventMatchers(
            directories: temporaryFeatureDirectories,
            configuration: .mockWith(
                eventMapper: RUMEventsMapper(
                    viewEventMapper: { viewEvent in
                        var viewEvent = viewEvent
                        viewEvent.view.url = "ModifiedViewURL"
                        viewEvent.view.name = "ModifiedViewName"
                        return viewEvent
                    },
                    errorEventMapper: { errorEvent in
                        var errorEvent = errorEvent
                        errorEvent.error.message = "Modified error message"
                        return errorEvent
                    },
                    resourceEventMapper: { resourceEvent in
                        var resourceEvent = resourceEvent
                        resourceEvent.resource.url = "https://foo.com?q=modified-resource-url"
                        return resourceEvent
                    },
                    actionEventMapper: { actionEvent in
                        if actionEvent.action.type == .applicationStart {
                            return nil // drop `.applicationStart` action
                        } else {
                            var actionEvent = actionEvent
                            actionEvent.action.target?.name = "Modified tap action name"
                            return actionEvent
                        }
                    }
                )
            ),
            dependencies: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
            )
        )
        defer { RUMFeature.instance = nil }

        let monitor = RUMMonitor.initialize()

        monitor.startView(viewController: mockView, name: "OriginalViewName")
        monitor.startResourceLoading(resourceKey: "/resource/1", url: URL(string: "https://foo.com?q=original-resource-url")!)
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.addUserAction(type: .tap, name: "Original tap action name")
        monitor.addError(message: "Original error message")

        let rumEventMatchers = try RUMFeature.waitAndReturnRUMEventMatchers(count: 6)
        let sessions = try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers)

        XCTAssertEqual(sessions.count, 1, "All events should belong to a single RUM Session")
        let session = sessions[0]

        session.viewVisits[0].viewEvents.forEach { viewEvent in
            XCTAssertEqual(viewEvent.view.url, "ModifiedViewURL")
            XCTAssertEqual(viewEvent.view.name, "ModifiedViewName")
        }
        XCTAssertEqual(session.viewVisits[0].resourceEvents.count, 1)
        XCTAssertEqual(session.viewVisits[0].resourceEvents[0].resource.url, "https://foo.com?q=modified-resource-url")
        XCTAssertEqual(session.viewVisits[0].actionEvents.count, 1)
        XCTAssertEqual(session.viewVisits[0].actionEvents[0].action.target?.name, "Modified tap action name")
        XCTAssertEqual(session.viewVisits[0].errorEvents.count, 1)
        XCTAssertEqual(session.viewVisits[0].errorEvents[0].error.message, "Modified error message")
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
            case 2: monitor.addError(error: ErrorMock(), source: .custom)
            case 3: monitor.addError(message: .mockAny(), source: .custom)
            case 4: monitor.startResourceLoading(resourceKey: .mockAny(), request: .mockAny())
            case 5: monitor.stopResourceLoading(resourceKey: .mockAny(), response: .mockAny())
            case 6: monitor.stopResourceLoadingWithError(resourceKey: .mockAny(), error: ErrorMock())
            case 7: monitor.stopResourceLoadingWithError(resourceKey: .mockAny(), errorMessage: .mockAny())
            case 8: monitor.startUserAction(type: .scroll, name: .mockRandom())
            case 9: monitor.stopUserAction(type: .scroll)
            case 10: monitor.addUserAction(type: .tap, name: .mockRandom())
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
            trackingConsent: .mockRandom(),
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
            trackingConsent: .mockRandom(),
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
            trackingConsent: .mockRandom(),
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

    func testGivenRUMAutoInstrumentationEnabled_whenRUMMonitorIsNotRegistered_itPrintsWarningsOnEachEvent() throws {
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: Datadog.Configuration
                .builderUsing(rumApplicationID: .mockAny(), clientToken: .mockAny(), environment: .mockAny())
                .trackURLSession(firstPartyHosts: [.mockAny()])
                .trackUIKitRUMViews(using: UIKitRUMViewsPredicateMock(result: .init(name: .mockAny())))
                .trackUIKitActions(true)
                .build()
        )

        let output = LogOutputMock()
        userLogger = .mockWith(logOutput: output)

        // Given
        let resourcesHandler = try XCTUnwrap(URLSessionAutoInstrumentation.instance?.interceptor.handler)
        let viewsHandler = try XCTUnwrap(RUMAutoInstrumentation.instance?.views?.handler)
        let userActionsHandler = try XCTUnwrap(RUMAutoInstrumentation.instance?.userActions?.handler)

        // When
        XCTAssertTrue(Global.rum is DDNoopRUMMonitor)

        // Then
        resourcesHandler.notify_taskInterceptionCompleted(interception: TaskInterception(request: .mockAny(), isFirstParty: .mockAny()))
        XCTAssertEqual(output.recordedLog?.status, .warn)
        XCTAssertEqual(
            output.recordedLog?.message,
            """
            RUM Resource was completed, but no `RUMMonitor` is registered on `Global.rum`. RUM auto instrumentation will not work.
            Make sure `Global.rum = RUMMonitor.initialize()` is called before any network request is send.
            """
        )

        viewsHandler.notify_viewDidAppear(viewController: mockView, animated: .mockAny())
        XCTAssertEqual(output.recordedLog?.status, .warn)
        XCTAssertEqual(
            output.recordedLog?.message,
            """
            RUM View was started, but no `RUMMonitor` is registered on `Global.rum`. RUM auto instrumentation will not work.
            Make sure `Global.rum = RUMMonitor.initialize()` is called before any `UIViewController` is presented.
            """
        )

        let mockWindow = UIWindow(frame: .zero)
        let mockUIControl = UIControl()
        mockWindow.addSubview(mockUIControl)
        userActionsHandler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touches: [.mockWith(phase: .ended, view: mockUIControl)])
        )
        XCTAssertEqual(output.recordedLog?.status, .warn)
        XCTAssertEqual(
            output.recordedLog?.message,
            """
            RUM Action was detected, but no `RUMMonitor` is registered on `Global.rum`. RUM auto instrumentation will not work.
            Make sure `Global.rum = RUMMonitor.initialize()` is called before any action happens.
            """
        )

        URLSessionAutoInstrumentation.instance?.swizzler.unswizzle()
        RUMAutoInstrumentation.instance?.views?.swizzler.unswizzle()
        RUMAutoInstrumentation.instance?.userActions?.swizzler.unswizzle()

        try Datadog.deinitializeOrThrow()
    }

    // MARK: - Internal attributes

    func testHandlingInternalTimestampAttribute() throws {
        RUMFeature.instance = .mockNoOp()
        defer { RUMFeature.instance = nil }

        var mockCommand = RUMCommandMock()
        mockCommand.attributes = [
            RUMAttribute.internalTimestamp: Int64(1_000) // 1000 in miliseconds
        ]

        let monitor = try XCTUnwrap(RUMMonitor.initialize() as? RUMMonitor)

        let transformedCommand = monitor.transform(command: mockCommand)
        XCTAssertTrue(transformedCommand.attributes.isEmpty)
        XCTAssertNotEqual(transformedCommand.time, mockCommand.time)
        XCTAssertEqual(transformedCommand.time, Date(timeIntervalSince1970: 1)) // 1 in seconds
    }

    // MARK: - Private helpers

    private var expectedAttributes = [String: String]()
    private func setGlobalAttributes(of monitor: DDRUMMonitor) {
        let key = String.mockRandom()
        let value = String.mockRandom()
        monitor.addAttribute(forKey: key, value: value)
        expectedAttributes = ["context.\(key)": value]
    }

    private func verifyGlobalAttributes(in matchers: [RUMEventMatcher]) {
        for matcher in matchers {
            expectedAttributes.forEach { attrKey, attrValue in
                XCTAssertEqual(try? matcher.attribute(forKeyPath: attrKey), attrValue)
            }
        }
    }
}

class RUMHTTPMethodTests: XCTestCase {
    func testItCanBeInitializedFromURLRequest() {
        XCTAssertEqual(
            RUMMethod(httpMethod: "get".randomcased()), .get
        )
        XCTAssertEqual(
            RUMMethod(httpMethod: "post".randomcased()), .post
        )
        XCTAssertEqual(
            RUMMethod(httpMethod: "put".randomcased()), .put
        )
        XCTAssertEqual(
            RUMMethod(httpMethod: "delete".randomcased()), .delete
        )
        XCTAssertEqual(
            RUMMethod(httpMethod: "head".randomcased()), .head
        )
        XCTAssertEqual(
            RUMMethod(httpMethod: "patch".randomcased()), .patch
        )
    }

    func testWhenInitializingFromURLRequest_itDefaultsToGET() {
        XCTAssertEqual(
            RUMMethod(httpMethod: "unknown_method".randomcased()), .get
        )
    }
}

class RUMResourceKindTests: XCTestCase {
    func testWhenInitializedWithResponse_itReturnsKindBasedOnMIMEType() {
        let fixtures: [(mime: String, kind: RUMResourceType)] = [
            (mime: "image/png", kind: .image),
            (mime: "video/mpeg", kind: .media),
            (mime: "audio/ogg", kind: .media),
            (mime: "font/otf", kind: .font),
            (mime: "text/css", kind: .css),
            (mime: "text/css; charset=UTF-8", kind: .css),
            (mime: "text/javascript", kind: .js),
            (mime: "text/javascript; charset=UTF-8", kind: .js),
        ]

        fixtures.forEach { mime, expectedKind in
            XCTAssertEqual(
                RUMResourceType(response: .mockWith(mimeType: mime.randomcased())),
                expectedKind
            )
        }
    }

    func testWhenInitializedWithPOSTorPUTorDELETErequest_itReturnsXHR() {
        XCTAssertEqual(
            RUMResourceType(request: .mockWith(httpMethod: "POST".randomcased())), .xhr
        )
        XCTAssertEqual(
            RUMResourceType(request: .mockWith(httpMethod: "PUT".randomcased())), .xhr
        )
        XCTAssertEqual(
            RUMResourceType(request: .mockWith(httpMethod: "DELETE".randomcased())), .xhr
        )
    }

    func testWhenInitializedWithGETorHEADorPATCHrequest_itReturnsNil() {
        XCTAssertNil(
            RUMResourceType(request: .mockWith(httpMethod: "GET".randomcased()))
        )
        XCTAssertNil(
            RUMResourceType(request: .mockWith(httpMethod: "HEAD".randomcased()))
        )
        XCTAssertNil(
            RUMResourceType(request: .mockWith(httpMethod: "PATCH".randomcased()))
        )
    }

    func testWhenInitializingFromHTTPURLResponse_itDefaultsToOther() {
        XCTAssertEqual(
            RUMResourceType(response: .mockWith(mimeType: "unknown/type")), .other
        )
    }
}
