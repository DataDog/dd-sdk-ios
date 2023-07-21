/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import UIKit
import TestUtilities
@testable import Datadog

class RUMMonitorTests: XCTestCase {
    private var core: DatadogCoreProxy! // swiftlint:disable:this implicitly_unwrapped_optional

    override func setUp() {
        super.setUp()
        core = DatadogCoreProxy()
    }

    override func tearDown() {
        core.flushAndTearDown()
        core = nil
        super.tearDown()
    }

    /// Creates `RUMMonitor` instance for tests.
    /// The only difference vs. `RUMMonitor.initialize()` is that we disable RUM view updates sampling to get deterministic behaviour.
    private func createTestableRUMMonitor() throws -> DDRUMMonitor {
        let rumFeature: RUMFeature = try XCTUnwrap(core.v1.feature(RUMFeature.self), "RUM feature must be initialized before creating `RUMMonitor`")
        return RUMMonitor(
            core: core,
            dependencies: RUMScopeDependencies(
                core: core,
                rumFeature: rumFeature
            ),
            dateProvider: rumFeature.configuration.dateProvider
        )
    }

    // MARK: - Sending RUM events

    func testStartingViewIdentifiedByViewController() throws {
        let randomServiceName: String = .mockRandom()

        core.context = .mockWith(
            service: randomServiceName
        )

        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.stopView(viewController: mockView)
        monitor.startView(viewController: mockView)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)

        let firstVisit = session.viewVisits[0]
        XCTAssertEqual(firstVisit.viewEvents.last?.view.timeSpent, 1_000_000_000)

        let secondVisit = session.viewVisits[1]
        XCTAssertEqual(secondVisit.viewEvents.last?.view.action.count, 0)
    }

    func testStartingViewIdentifiedByStringKey() throws {
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        monitor.startView(key: "view1-key", name: "View1")
        monitor.stopView(key: "view1")
        monitor.startView(key: "view2-key", name: "View2")

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        XCTAssertEqual(session.viewVisits.count, 2)
        XCTAssertEqual(session.viewVisits[0].name, "View1")
        XCTAssertEqual(session.viewVisits[0].path, "view1-key")
        XCTAssertEqual(session.viewVisits[1].name, "View2")
        XCTAssertEqual(session.viewVisits[1].path, "view2-key")
    }

    func testStartingView_thenLoadingImageResourceWithRequest() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockWith(httpMethod: "GET"))
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockWith(statusCode: 200, mimeType: "image/png"))

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers().filterApplicationLaunchView()
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers[0].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 0)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[1].model(ofType: RUMResourceEvent.self) { rumModel in
            XCTAssertEqual(rumModel.resource.type, .image)
            XCTAssertEqual(rumModel.resource.statusCode, 200)
        }
        try rumEventMatchers[2].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 0)
            XCTAssertEqual(rumModel.view.resource.count, 1)
        }
    }

    func testStartingView_thenLoadingNativeResourceWithRequestWithMetrics() throws {
        guard #available(iOS 13, *) else {
            return // `URLSessionTaskMetrics` mocking doesn't work prior to iOS 13.0
        }

        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
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

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let resourceEvent = session.viewVisits[0].resourceEvents[0]
        XCTAssertEqual(resourceEvent.resource.type, .native, "POST Resources should always have the `.native` kind")
        XCTAssertEqual(resourceEvent.resource.statusCode, 200)
        XCTAssertEqual(resourceEvent.resource.duration, 4_000_000_000)
        XCTAssertEqual(resourceEvent.resource.dns!.start, 1_000_000_000)
        XCTAssertEqual(resourceEvent.resource.dns!.duration, 2_000_000_000)
    }

    func testStartingView_thenLoadingNativeResourceWithRequestWithExternalMetrics() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockWith(httpMethod: "POST"))

        let fetch = (start: Date.mockDecember15th2019At10AMUTC(),
                     end: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 12))
        let redirection = (start: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 1),
                           end: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 2))
        let dns = (start: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 3),
                   end: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 4))
        let connect = (start: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 5),
                       end: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 6))
        let ssl = (start: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 7),
                   end: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 8))
        let firstByte = (start: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 9),
                         end: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 10))
        let download = (start: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 11),
                        end: Date.mockDecember15th2019At10AMUTC(addingTimeInterval: 12))

        monitor.addResourceMetrics(
            resourceKey: "/resource/1",
            fetch: fetch,
            redirection: redirection,
            dns: dns,
            connect: connect,
            ssl: ssl,
            firstByte: firstByte,
            download: download,
            responseSize: 42
        )

        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockWith(statusCode: 200, mimeType: "image/png"))

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let resourceEvent = session.viewVisits[0].resourceEvents[0]
        XCTAssertEqual(resourceEvent.resource.type, .native, "POST Resources should always have the `.native` kind")
        XCTAssertEqual(resourceEvent.resource.statusCode, 200)

        XCTAssertEqual(resourceEvent.resource.duration, 12_000_000_000)

        XCTAssertEqual(resourceEvent.resource.redirect!.start, 1_000_000_000)
        XCTAssertEqual(resourceEvent.resource.redirect!.duration, 1_000_000_000)

        XCTAssertEqual(resourceEvent.resource.dns!.start, 3_000_000_000)
        XCTAssertEqual(resourceEvent.resource.dns!.duration, 1_000_000_000)

        XCTAssertEqual(resourceEvent.resource.connect!.start, 5_000_000_000)
        XCTAssertEqual(resourceEvent.resource.connect!.duration, 1_000_000_000)

        XCTAssertEqual(resourceEvent.resource.ssl!.start, 7_000_000_000)
        XCTAssertEqual(resourceEvent.resource.ssl!.duration, 1_000_000_000)

        XCTAssertEqual(resourceEvent.resource.firstByte!.start, 9_000_000_000)
        XCTAssertEqual(resourceEvent.resource.firstByte!.duration, 1_000_000_000)

        XCTAssertEqual(resourceEvent.resource.download!.start, 11_000_000_000)
        XCTAssertEqual(resourceEvent.resource.download!.duration, 1_000_000_000)
    }

    func testStartingView_thenLoadingResourceWithURL() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        let url: URL = .mockRandom()
        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceKey: "/resource/1", url: url)
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockWith(statusCode: 200, mimeType: "image/png"))

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let resourceEvent = session.viewVisits[0].resourceEvents[0]
        XCTAssertEqual(resourceEvent.resource.url, url.absoluteString)
        XCTAssertEqual(resourceEvent.resource.statusCode, 200)
        XCTAssertNil(resourceEvent.resource.provider?.type)
    }

    func testStartingView_thenLoadingResourceWithURLString() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceKey: "/resource/1", httpMethod: .post, urlString: "/some/url/string", attributes: [:])
        monitor.stopResourceLoading(resourceKey: "/resource/1", statusCode: 333, kind: .beacon)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let resourceEvent = session.viewVisits[0].resourceEvents[0]
        XCTAssertEqual(resourceEvent.resource.url, "/some/url/string")
        XCTAssertEqual(resourceEvent.resource.statusCode, 333)
        XCTAssertEqual(resourceEvent.resource.type, .beacon)
        XCTAssertEqual(resourceEvent.resource.method, .post)
        XCTAssertNil(resourceEvent.resource.provider?.type)
    }

    func testLoadingResourceWithURL_thenMarksFirstPartyURLs() throws {
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                // .mockRandom always uses foo.com
                firstPartyHosts: .init(["foo.com": [.datadog]])
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        let url: URL = .mockRandom()
        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceKey: "/resource/1", url: url)
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockWith(statusCode: 200, mimeType: "image/png"))

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let resourceEvent = session.viewVisits[0].resourceEvents[0]
        XCTAssertEqual(resourceEvent.resource.provider?.type, RUMResourceEvent.Resource.Provider.ProviderType.firstParty)
    }

    func testLoadingResourceWithURLString_thenMarksFirstPartyURLs() throws {
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                firstPartyHosts: .init(["foo.com": [.datadog]])
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceKey: "/resource/1", httpMethod: .post, urlString: "http://www.foo.com/some/url/string", attributes: [:])
        monitor.stopResourceLoading(resourceKey: "/resource/1", statusCode: 333, kind: .beacon)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)

        let session = try XCTUnwrap(try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first)
        let resourceEvent = session.viewVisits[0].resourceEvents[0]
        XCTAssertEqual(resourceEvent.resource.provider?.type, RUMResourceEvent.Resource.Provider.ProviderType.firstParty)
    }

    func testStartingView_thenTappingButton() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        let actionName = String.mockRandom()
        monitor.startView(viewController: mockView)
        monitor.addUserAction(type: .tap, name: actionName)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers[0].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .applicationStart)
        }
        // Start ApplicationLaunch view
        try rumEventMatchers[1].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        // Stop ApplicationLaunch view
        try rumEventMatchers[2].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[3].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 0)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
        try rumEventMatchers[4].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.type, .tap)
            XCTAssertEqual(rumModel.action.target?.name, actionName)
        }
        try rumEventMatchers[5].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 0)
        }
    }

    func testStartingView_thenLoadingResources_whileScrolling() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll, name: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockWith(httpMethod: "GET"))
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockWith(statusCode: 200))
        monitor.startResourceLoading(resourceKey: "/resource/2", request: .mockWith(httpMethod: "POST"))
        monitor.stopResourceLoading(resourceKey: "/resource/2", response: .mockWith(statusCode: 202))
        monitor.stopUserAction(type: .scroll)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers().filterApplicationLaunchView()
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers[0].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 0)
            XCTAssertEqual(rumModel.view.resource.count, 0)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
        var userActionID: String?
        try rumEventMatchers[1].model(ofType: RUMResourceEvent.self) { rumModel in
            userActionID = rumModel.action?.id.stringValue
            XCTAssertEqual(rumModel.resource.statusCode, 200)
            XCTAssertEqual(rumModel.resource.method, .get)
        }
        XCTAssertNotNil(userActionID, "Resource should be associated with the User Action that issued its loading")
        try rumEventMatchers[2].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 0)
            XCTAssertEqual(rumModel.view.resource.count, 1)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
        try rumEventMatchers[3].model(ofType: RUMResourceEvent.self) { rumModel in
            XCTAssertEqual(rumModel.resource.statusCode, 202)
            XCTAssertEqual(rumModel.resource.method, .post)
        }
        try rumEventMatchers[4].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 0)
            XCTAssertEqual(rumModel.view.resource.count, 2)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
        try rumEventMatchers[5].model(ofType: RUMActionEvent.self) { rumModel in
            XCTAssertEqual(rumModel.action.resource?.count, 2)
            XCTAssertEqual(rumModel.action.error?.count, 0)
            XCTAssertEqual(rumModel.action.id, userActionID)
        }
        try rumEventMatchers[6].model(ofType: RUMViewEvent.self) { rumModel in
            XCTAssertEqual(rumModel.view.action.count, 1)
            XCTAssertEqual(rumModel.view.resource.count, 2)
            XCTAssertEqual(rumModel.view.error.count, 0)
        }
    }

    func testStartingView_thenIssuingErrors_whileScrolling() throws {
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 0.01)
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll, name: .mockAny())
#sourceLocation(file: "/user/abc/Foo.swift", line: 100)
        monitor.addError(message: "View error message", source: .source)
#sourceLocation()
        monitor.addError(message: "Another error message", source: .webview, stack: "Error stack")
        let customType: String = .mockRandom(among: .alphanumerics)
        monitor.addError(message: "Another error message", type: customType, source: .webview, stack: "Error stack")
        monitor.stopUserAction(type: .scroll)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)

        let rumSession = try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first.unwrapOrThrow()
        XCTAssertEqual(rumSession.viewVisits.count, 1, "Session should track one view")

        let firstView = rumSession.viewVisits[0]
        XCTAssertEqual(firstView.viewEvents.last?.view.action.count, 1, "View must track 1 action")
        XCTAssertEqual(firstView.viewEvents.last?.view.resource.count, 0, "View must track no resources")
        XCTAssertEqual(firstView.viewEvents.last?.view.error.count, 3, "View must track 3 errors")

        let firstAction = firstView.actionEvents[0]
        XCTAssertEqual(firstAction.action.type, .scroll, "First action must be 'scroll'")
        XCTAssertEqual(firstAction.action.error?.count, 3, "First action must link 3 errors")

        let firstError = firstView.errorEvents[0]
        let secondError = firstView.errorEvents[1]
        let thirdError = firstView.errorEvents[2]
        XCTAssertEqual(firstError.error.message, "View error message")
        XCTAssertEqual(firstError.error.stack, "Foo.swift:100")
        XCTAssertEqual(firstError.error.source, .source)
        XCTAssertNil(firstError.error.type)
        XCTAssertEqual(secondError.error.message, "Another error message")
        XCTAssertEqual(secondError.error.stack, "Error stack")
        XCTAssertEqual(secondError.error.source, .webview)
        XCTAssertNil(secondError.error.type)
        XCTAssertEqual(thirdError.error.message, "Another error message")
        XCTAssertEqual(thirdError.error.stack, "Error stack")
        XCTAssertEqual(thirdError.error.source, .webview)
        XCTAssertEqual(thirdError.error.type, customType)

        XCTAssertEqual(firstAction.view.id, firstView.viewID, "Events must be linked to the view")
        XCTAssertEqual(firstError.view.id, firstView.viewID, "Events must be linked to the view")
        XCTAssertEqual(secondError.view.id, firstView.viewID, "Events must be linked to the view")
        XCTAssertEqual(thirdError.view.id, firstView.viewID, "Events must be linked to the view")
    }

    func testStartingAnotherViewBeforeFirstIsStopped_thenLoadingResourcesAfterTapingButton() throws {
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(
                    startingFrom: Date(),
                    advancingBySeconds: RUMUserActionScope.Constants.discreteActionTimeoutDuration
                )
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
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

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers().filterApplicationLaunchView()
        verifyGlobalAttributes(in: rumEventMatchers)
        try rumEventMatchers
            .lastRUMEvent(ofType: RUMViewEvent.self) { rumModel in rumModel.view.url == "FirstViewController" }
            .model(ofType: RUMViewEvent.self) { rumModel in
                XCTAssertEqual(rumModel.view.url, "FirstViewController")
                XCTAssertEqual(rumModel.view.name, "FirstViewController")
                XCTAssertEqual(rumModel.view.action.count, 0, "First View should track no actions")
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
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
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
        monitor.startResourceLoading(resourceKey: "/resource/5", request: URLRequest(url: .mockWith(pathComponent: "/resource/5")))
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.stopResourceLoadingWithError(resourceKey: "/resource/2", errorMessage: .mockAny())
        monitor.stopResourceLoading(resourceKey: "/resource/3", response: .mockAny())
        monitor.stopResourceLoading(resourceKey: "/resource/4", response: .mockAny())
        let customType: String = .mockRandom(among: .alphanumerics)
        monitor.stopResourceLoadingWithError(resourceKey: "/resource/5", errorMessage: .mockAny(), type: customType)
        monitor.stopView(viewController: view2)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)

        let rumSession = try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers).first.unwrapOrThrow()
        XCTAssertEqual(rumSession.viewVisits.count, 2, "Session should track two views")

        let firstView = rumSession.viewVisits[0]
        let secondView = rumSession.viewVisits[1]
        XCTAssertEqual(firstView.viewEvents.last?.view.url, "FirstViewController")
        XCTAssertEqual(firstView.viewEvents.last?.view.name, "FirstViewController")
        XCTAssertEqual(firstView.viewEvents.last?.view.resource.count, 1, "First view must track 1 resource")
        XCTAssertEqual(firstView.viewEvents.last?.view.error.count, 1, "First view must track 1 resource error")
        XCTAssertEqual(secondView.viewEvents.last?.view.url, "SecondViewController")
        XCTAssertEqual(secondView.viewEvents.last?.view.name, "SecondViewController")
        XCTAssertEqual(secondView.viewEvents.last?.view.resource.count, 2, "Second view must track 2 resources")
        XCTAssertEqual(secondView.viewEvents.last?.view.error.count, 1, "Second view must track 1 resource error")

        let firstResource = firstView.resourceEvents[0]
        let secondResourceError = firstView.errorEvents[0]
        let thirdResource = secondView.resourceEvents[0]
        let fourthResource = secondView.resourceEvents[1]
        let fifthResourceError = secondView.errorEvents[0]
        XCTAssertTrue(firstResource.resource.url.hasSuffix("/resource/1"))
        XCTAssertTrue(secondResourceError.error.resource?.url.hasSuffix("/resource/2") ?? false)
        XCTAssertTrue(thirdResource.resource.url.hasSuffix("/resource/3"))
        XCTAssertTrue(fourthResource.resource.url.hasSuffix("/resource/4"))
        XCTAssertTrue(fifthResourceError.error.resource?.url.hasSuffix("/resource/5") ?? false)
        XCTAssertEqual(firstResource.view.id, firstView.viewID, "Events must be linked to their views")
        XCTAssertEqual(secondResourceError.view.id, firstView.viewID, "Events must be linked to their views")
        XCTAssertEqual(thirdResource.view.id, secondView.viewID, "Events must be linked to their views")
        XCTAssertEqual(fourthResource.view.id, secondView.viewID, "Events must be linked to their views")
        XCTAssertEqual(fifthResourceError.view.id, secondView.viewID, "Events must be linked to their views")

        XCTAssertNil(secondResourceError.error.type, "Second resource's error must have no type")
        XCTAssertEqual(fifthResourceError.error.type, customType, "Second resource's error must have custom type")
    }

    func testStartingView_thenTappingButton_thenTappingAnotherButton() throws {
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()

        monitor.startView(viewController: mockView)
        monitor.addUserAction(type: .tap, name: "1st action")
        monitor.addUserAction(type: .swipe, name: "2nd action")
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
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
                XCTAssertEqual(rumModel.view.action.count, 2)
            }
    }

    // MARK: - Sending user info

    func testWhenUserInfoIsProvided_itIsSendWithAllEvents() throws {
        core.context = .mockWith(
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

        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll, name: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/2", request: .mockAny())
        monitor.stopUserAction(type: .scroll)
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.stopResourceLoadingWithError(resourceKey: "/resource/2", errorMessage: .mockAny())
        monitor.addError(message: .mockAny(), source: .source)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        let expectedUserInfo = RUMUser(email: "foo@bar.com", id: "abc-123", name: "Foo", usrInfo: [
            "str": AnyEncodable("value"),
            "int": AnyEncodable(11_235),
            "bool": AnyEncodable(true)
        ])
        try rumEventMatchers.forEach { event in
            XCTAssertEqual(try event.attribute(forKeyPath: "usr.str"), "value")
            XCTAssertEqual(try event.attribute(forKeyPath: "usr.int"), 11_235)
            XCTAssertEqual(try event.attribute(forKeyPath: "usr.bool"), true) // swiftlint:disable:this xct_specific_matcher
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMActionEvent.self) { action in
            DDAssertReflectionEqual(action.usr, expectedUserInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMViewEvent.self) { view in
            DDAssertReflectionEqual(view.usr, expectedUserInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMResourceEvent.self) { resource in
            DDAssertReflectionEqual(resource.usr, expectedUserInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMErrorEvent.self) { error in
            DDAssertReflectionEqual(error.usr, expectedUserInfo)
        }
    }

    // MARK: - Sending connectivity info

    func testWhenNetworkAndCarrierInfoAreProvided_thenConnectivityInfoIsSendWithAllEvents() throws {
        core.context = .mockWith(
            networkConnectionInfo: .mockWith(reachability: .yes, availableInterfaces: [.cellular]),
            carrierInfo: .mockWith(carrierName: "Carrier Name", radioAccessTechnology: .GPRS)
        )

        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()

        monitor.startView(viewController: mockView)
        monitor.startUserAction(type: .scroll, name: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/2", request: .mockAny())
        monitor.stopUserAction(type: .scroll)
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.stopResourceLoadingWithError(resourceKey: "/resource/2", errorMessage: .mockAny())
        monitor.addError(message: .mockAny(), source: .source)
        monitor.stopView(viewController: mockView)

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        let expectedConnectivityInfo = RUMConnectivity(
            cellular: RUMConnectivity.Cellular(carrierName: "Carrier Name", technology: "GPRS"),
            interfaces: [.cellular],
            status: .connected
        )
        try rumEventMatchers.forEachRUMEvent(ofType: RUMActionEvent.self) { action in
            DDAssertReflectionEqual(action.connectivity, expectedConnectivityInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMViewEvent.self) { view in
            DDAssertReflectionEqual(view.connectivity, expectedConnectivityInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMResourceEvent.self) { resource in
            DDAssertReflectionEqual(resource.connectivity, expectedConnectivityInfo)
        }
        try rumEventMatchers.forEachRUMEvent(ofType: RUMErrorEvent.self) { error in
            DDAssertReflectionEqual(error.connectivity, expectedConnectivityInfo)
        }
    }

    // MARK: - Sending Attributes

    func testSendingAttributes() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let view1 = createMockView(viewControllerClassName: "FirstViewController")
        let view2 = createMockView(viewControllerClassName: "SecondViewController")

        let monitor = try createTestableRUMMonitor()

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

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        let firstViewEvent = try rumEventMatchers
            .lastRUMEvent(ofType: RUMViewEvent.self) { rumModel in rumModel.view.url == "FirstViewController" }

        XCTAssertNil(try? firstViewEvent.attribute(forKeyPath: "attribute1") as String)
        XCTAssertNil(try? firstViewEvent.attribute(forKeyPath: "attribute2") as String)
        XCTAssertEqual(try firstViewEvent.attribute(forKeyPath: "context.attribute1") as String, "changed value 1")

        // TODO: RUMM-2844 [V2 regression?] RUM monitor `removeAttribute(forKey:)` behaves differently than in V1
//        XCTAssertEqual(try firstViewEvent.attribute(forKeyPath: "context.attribute2") as String, "value 2")

        let secondViewEvent = try rumEventMatchers
            .lastRUMEvent(ofType: RUMViewEvent.self) { rumModel in rumModel.view.url == "SecondViewController" }

        XCTAssertNil(try? secondViewEvent.attribute(forKeyPath: "attribute1") as String)
        XCTAssertEqual(try secondViewEvent.attribute(forKeyPath: "context.attribute1") as String, "changed value 1")
        XCTAssertNil(try? secondViewEvent.attribute(forKeyPath: "context.attribute2") as String)
    }

    // TODO: RUMM-2844 [V2 regression?] RUM monitor `removeAttribute(forKey:)` behaves differently than in V1
//    func testWhenViewIsStarted_attributesCanBeAddedOrUpdatedButNotRemoved() throws {
//        let rum: RUMFeature = .mockByRecordingRUMEventMatchers()
//        core.register(feature: rum)
//
//        let monitor = try createTestableRUMMonitor()
//
//        monitor.addAttribute(forKey: "a1", value: "foo1")
//        monitor.addAttribute(forKey: "a2", value: "foo2")
//
//        monitor.startView(viewController: mockView)
//
//        monitor.addAttribute(forKey: "a1", value: "bar1") // update
//        monitor.removeAttribute(forKey: "a2") // remove
//        monitor.addAttribute(forKey: "a3", value: "foo3") // add
//
//        monitor.stopView(viewController: mockView)
//
//        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
//        let lastViewUpdate = try rumEventMatchers.lastRUMEvent(ofType: RUMViewEvent.self)
//
//        XCTAssertNil(try? lastViewUpdate.attribute(forKeyPath: "a1") as String)
//        XCTAssertNil(try? lastViewUpdate.attribute(forKeyPath: "a2") as String)
//        XCTAssertNil(try? lastViewUpdate.attribute(forKeyPath: "a3") as String)
//        try XCTAssertEqual(lastViewUpdate.attribute(forKeyPath: "context.a1"), "bar1", "The value should be updated")
//        try XCTAssertEqual(lastViewUpdate.attribute(forKeyPath: "context.a2"), "foo2", "The attribute should not be removed")
//        try XCTAssertEqual(lastViewUpdate.attribute(forKeyPath: "context.a3"), "foo3", "The attribute should be added")
//    }

    // MARK: - Sending Custom Timings

    func testStartingView_thenAddingTiming() throws {
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(
                    startingFrom: Date(),
                    advancingBySeconds: 1
                )
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        setGlobalAttributes(of: monitor)

        monitor.startView(viewController: mockView)
        monitor.addTiming(name: "timing1")
        monitor.addTiming(name: "timing2")
        monitor.addTiming(name: "timing3_.@$-()&+=Д")

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        verifyGlobalAttributes(in: rumEventMatchers)
        let lastViewUpdate = try rumEventMatchers.lastRUMEvent(ofType: RUMViewEvent.self)
        XCTAssertEqual(try lastViewUpdate.timing(named: "timing1"), 1_000_000_000)
        XCTAssertEqual(try lastViewUpdate.timing(named: "timing2"), 2_000_000_000)
        XCTAssertEqual(try lastViewUpdate.timing(named: "timing3_.@$-______"), 3_000_000_000)
    }

    // MARK: - Feature Flags

    func testStartingView_thenAddingFeatureFlags() throws {
        // Given
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(
                    startingFrom: Date(),
                    advancingBySeconds: 1
                )
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        monitor.startView(viewController: mockView)

        // When
        let flagName: String = .mockRandom()
        let flagValue: Bool = .mockRandom()
        monitor.addFeatureFlagEvaluation(name: flagName, value: flagValue)

        let rumEventMatchers = core.waitAndReturnEvents(of: RUMFeature.self, ofType: RUMViewEvent.self)
        let lastViewUpdate = try XCTUnwrap(rumEventMatchers.last)
        let flags = try XCTUnwrap(lastViewUpdate.featureFlags)
        XCTAssertEqual(flags.featureFlagsInfo[flagName] as? Bool, flagValue)
    }

    func testGivenActiveViewWithFlags_thenAddingError_sendsFlags() throws {
        // Given
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(
                    startingFrom: Date(),
                    advancingBySeconds: 1
                )
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        monitor.startView(viewController: mockView)
        let flagName: String = .mockRandom()
        let flagValue: Bool = .mockRandom()
        monitor.addFeatureFlagEvaluation(name: flagName, value: flagValue)

        // When
        monitor.addError(message: .mockAny())

        // Then
        let rumErrorEvents = core.waitAndReturnEvents(of: RUMFeature.self, ofType: RUMErrorEvent.self)
        let lastError = try XCTUnwrap(rumErrorEvents.last)
        let flags = try XCTUnwrap(lastError.featureFlags)
        XCTAssertEqual(flags.featureFlagsInfo[flagName] as? Bool, flagValue)
    }

    func testGivenAnActiveViewWithFlags_startingANewView_resetsFlags() throws {
        // Given
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(
                    startingFrom: Date(),
                    advancingBySeconds: 1
                )
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        monitor.startView(viewController: mockView)
        monitor.addFeatureFlagEvaluation(name: .mockAny(), value: String.mockAny())

        // When
        let mockSecondView = createMockViewInWindow()
        monitor.startView(viewController: mockSecondView)

        // Then
        let rumEventMatchers = core.waitAndReturnEvents(of: RUMFeature.self, ofType: RUMViewEvent.self)
        let lastViewUpdate = try XCTUnwrap(rumEventMatchers.last)
        let flags = try XCTUnwrap(lastViewUpdate.featureFlags)
        XCTAssertEqual(flags.featureFlagsInfo.count, 0)
    }

    // MARK: - RUM New Session

    func testStartingViewCreatesNewSession() throws {
        let keepAllSessions: Bool = .random()
        let expectation = self.expectation(description: "onSessionStart is called")

        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                sessionSampler: keepAllSessions ? .mockKeepAll() : .mockRejectAll(),
                onSessionStart: { sessionId, isDiscarded in
                    XCTAssertTrue(sessionId.matches(regex: .uuidRegex))
                    XCTAssertEqual(isDiscarded, !keepAllSessions)
                    expectation.fulfill()
                }
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        monitor.startView(viewController: mockView)

        waitForExpectations(timeout: 0.5)
    }

    // MARK: - RUM Events Dates Correction

    func testGivenTimeDifferenceBetweenDeviceAndServer_whenCollectingRUMEvents_thenEventsDateUseServerTime() throws {
        // Given
        let deviceTime: Date = .mockDecember15th2019At10AMUTC()
        var serverTimeOffset = TimeInterval.random(in: 600..<1_200).rounded() // 10 - 20 minutes difference
        serverTimeOffset = serverTimeOffset * (Bool.random() ? 1 : -1) // positive or negative difference

        core.context = .mockWith(
            serverTimeOffset: serverTimeOffset
        )

        // When
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(
                    startingFrom: deviceTime,
                    advancingBySeconds: 1 // short advancing, so all events will be collected less than a minute after `deviceTime`
                )
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()

        monitor.startView(viewController: mockView)
        monitor.addUserAction(type: .tap, name: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/1", request: .mockAny())
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.startResourceLoading(resourceKey: "/resource/2", url: .mockAny())
        monitor.stopResourceLoadingWithError(resourceKey: "/resource/2", errorMessage: .mockAny())
        monitor.addError(message: .mockAny())

        // Then
        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
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
        let earliestServerTime = deviceTime.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds

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

    // MARK: - Launching SDKInit Command
    func testWhenInitializing_itSendsSDKInitCommand_thenSetsTheSessionId() throws {
        //Given
        let expectation = self.expectation(description: "sessionId is called")

        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                onSessionStart: { sessionId, isDiscarded in
                    XCTAssertTrue(sessionId.matches(regex: .uuidRegex))
                    expectation.fulfill()
                }
            )
        )

        core.register(feature: rum)

        //When
        _ = try createTestableRUMMonitor()

        //Then
        waitForExpectations(timeout: 0.5)
    }

    // MARK: - Tracking App Launch Events

    func testWhenInitializing_itStartsApplicationLaunchView_withLaunchTime() throws {
        // Given
        let launchDate: Date = .mockDecember15th2019At10AMUTC()
        let sdkInitDate = launchDate.addingTimeInterval(10)

        core.context = .mockWith(
            sdkInitDate: sdkInitDate,
            launchTime: LaunchTime(
                launchTime: nil,
                launchDate: launchDate,
                isActivePrewarm: false
            )
        )

        // When
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(
                    startingFrom: sdkInitDate.addingTimeInterval(10),
                    advancingBySeconds: 1
                )
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        monitor.startView(viewController: mockView)

        // Then
        let viewEvents = core.waitAndReturnEvents(of: RUMFeature.self, ofType: RUMViewEvent.self)
        let view = try XCTUnwrap(viewEvents.first)

        XCTAssertEqual(view.view.name, RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName)
        XCTAssertEqual(view.view.url, RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL)
        XCTAssertEqual(view.date, launchDate.timeIntervalSince1970.toInt64Milliseconds)
    }

    func testWhenInitializingWithActivePrewarm_itStartsApplicationLaunchView_withSdkInitDate() throws {
        // Given
        let launchDate: Date = .mockDecember15th2019At10AMUTC()
        let sdkInitDate = launchDate.addingTimeInterval(10)

        core.context = .mockWith(
            sdkInitDate: sdkInitDate,
            launchTime: LaunchTime(
                launchTime: nil,
                launchDate: launchDate,
                isActivePrewarm: true
            )
        )

        // When
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(
                    startingFrom: sdkInitDate.addingTimeInterval(10),
                    advancingBySeconds: 1
                )
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()
        monitor.startView(viewController: mockView)

        // Then
        let viewEvents = core.waitAndReturnEvents(of: RUMFeature.self, ofType: RUMViewEvent.self)
        let view = try XCTUnwrap(viewEvents.first)

        XCTAssertEqual(view.view.name, RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName)
        XCTAssertEqual(view.view.url, RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL)
        XCTAssertEqual(view.date, sdkInitDate.timeIntervalSince1970.toInt64Milliseconds)
    }

    func testWhenCollectingEventsBeforeStartingFirstView_itTracksThemWithinApplicationLaunchView() throws {
        // Given
        let launchDate: Date = .mockDecember15th2019At10AMUTC()
        let sdkInitDate = launchDate.addingTimeInterval(10)

        core.context = .mockWith(
            sdkInitDate: sdkInitDate,
            launchTime: LaunchTime(
                launchTime: nil,
                launchDate: launchDate,
                isActivePrewarm: false
            )
        )

        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                dateProvider: RelativeDateProvider(
                    startingFrom: sdkInitDate.addingTimeInterval(1),
                    advancingBySeconds: 1
                )
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()

        // When
        monitor.addUserAction(type: .custom, name: "A1")
        monitor.addError(message: "E1")
        monitor.startResourceLoading(resourceKey: "R1", url: URL(string: "https://foo.com/R1")!)
        monitor.startView(key: "FirstView")
        monitor.addUserAction(type: .tap, name: "A2")
        monitor.stopResourceLoading(resourceKey: "R1", statusCode: 200, kind: .native)

        // Then
        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        let session = try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers)[0]

        XCTAssertNotNil(session.applicationLaunchView)
        XCTAssertEqual(session.viewVisits.count, 1, "It should track 1 views")

        let appLaunchView = try XCTUnwrap(session.applicationLaunchView)
        let launchDateInMilliseconds = launchDate.timeIntervalSince1970.toInt64Milliseconds
        let sdkInitDateInMilliseconds = sdkInitDate.timeIntervalSince1970.toInt64Milliseconds

        XCTAssertEqual(appLaunchView.name, "ApplicationLaunch", "It should track 'ApplicationLaunch' view")
        XCTAssertEqual(appLaunchView.viewEvents.first?.date, launchDateInMilliseconds, "'ApplicationLaunch' view should start at launch time")
        XCTAssertEqual(appLaunchView.actionEvents.count, 2, "'ApplicationLaunch' should track 2 actions")
        XCTAssertEqual(appLaunchView.actionEvents[0].action.type, .applicationStart, "'ApplicationLaunch' should track 'application start' action")
        XCTAssertEqual(appLaunchView.actionEvents[0].date, launchDateInMilliseconds, "'application start' action should be tracked at launch time")
        XCTAssertEqual(appLaunchView.actionEvents[1].action.target?.name, "A1", "'ApplicationLaunch' should track 'A1' action")
        XCTAssertGreaterThan(appLaunchView.actionEvents[1].date, sdkInitDateInMilliseconds, "'A1' action should be tracked after SDK init")
        XCTAssertEqual(appLaunchView.errorEvents.count, 1, "'ApplicationLaunch' should track 1 error")
        XCTAssertEqual(appLaunchView.errorEvents[0].error.message, "E1", "'ApplicationLaunch' should track 'E1' error")
        XCTAssertEqual(appLaunchView.resourceEvents.count, 1, "'ApplicationLaunch' should track 1 resource")
        XCTAssertEqual(appLaunchView.resourceEvents[0].resource.url, "https://foo.com/R1", "'ApplicationLaunch' should track 'R1' resource")

        let userView = session.viewVisits[0]
        XCTAssertEqual(userView.name, "FirstView", "It should track user view")
        XCTAssertEqual(userView.actionEvents.count, 1, "User view should track 1 action")
        XCTAssertEqual(userView.actionEvents[0].action.target?.name, "A2", "User view should track 'A2' action")
    }

    // MARK: - Data Scrubbing

    func testModifyingEventsBeforeTheyGetSend() throws {
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                viewEventMapper: { viewEvent in
                    if viewEvent.view.url == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL {
                        return viewEvent
                    }

                    var viewEvent = viewEvent
                    viewEvent.view.url = "ModifiedViewURL"
                    viewEvent.view.name = "ModifiedViewName"
                    return viewEvent
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
                },
                errorEventMapper: { errorEvent in
                    var errorEvent = errorEvent
                    errorEvent.error.message = "Modified error message"
                    return errorEvent
                },
                longTaskEventMapper: { longTaskEvent in
                    var mutableLongTaskEvent = longTaskEvent
                    mutableLongTaskEvent.view.name = "ModifiedLongTaskViewName"
                    return mutableLongTaskEvent
                },
                dateProvider: RelativeDateProvider(startingFrom: Date(), advancingBySeconds: 1)
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()

        monitor.startView(viewController: mockView, name: "OriginalViewName")
        monitor.startResourceLoading(resourceKey: "/resource/1", url: URL(string: "https://foo.com?q=original-resource-url")!)
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.addUserAction(type: .tap, name: "Original tap action name")
        monitor.addError(message: "Original error message")

        let cmdSubscriber = try XCTUnwrap(monitor as? RUMMonitor)
        cmdSubscriber.process(command: RUMAddLongTaskCommand(time: Date(), attributes: [:], duration: 1.0))

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
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
        XCTAssertEqual(session.viewVisits[0].longTaskEvents[0].view.name, "ModifiedLongTaskViewName")
    }

    func testDroppingEventsBeforeTheyGetSent() throws {
        let rum: RUMFeature = .mockWith(
            configuration: .mockWith(
                resourceEventMapper: { _ in nil },
                actionEventMapper: { event in
                    return event.action.type == .applicationStart ? event : nil
                },
                errorEventMapper: { _ in nil },
                longTaskEventMapper: { _ in nil }
            )
        )
        core.register(feature: rum)

        let monitor = try createTestableRUMMonitor()

        monitor.startView(viewController: mockView)
        monitor.startResourceLoading(resourceKey: "/resource/1", url: .mockAny())
        monitor.stopResourceLoading(resourceKey: "/resource/1", response: .mockAny())
        monitor.addUserAction(type: .tap, name: .mockAny())
        monitor.addError(message: .mockAny())

        let cmdSubscriber = try XCTUnwrap(monitor as? RUMMonitor)
        cmdSubscriber.process(command: RUMAddLongTaskCommand(time: Date(), attributes: [:], duration: 1.0))

        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()
        let sessions = try RUMSessionMatcher.groupMatchersBySessions(rumEventMatchers)

        XCTAssertEqual(sessions.count, 1, "All events should belong to a single RUM Session")
        let session = sessions[0]

        XCTAssertNotEqual(session.viewVisits[0].viewEvents.count, 0)
        let lastEvent = session.viewVisits[0].viewEvents.last!
        XCTAssertEqual(lastEvent.view.resource.count, 0, "resource.count should reflect all resource events being dropped.")
        XCTAssertEqual(lastEvent.view.action.count, 0, "action.count should reflect all action events being dropped.")
        XCTAssertEqual(lastEvent.view.error.count, 0, "error.count should reflect all error events being dropped.")
        XCTAssertEqual(session.viewVisits[0].resourceEvents.count, 0)
        XCTAssertEqual(session.viewVisits[0].actionEvents.count, 0)
        XCTAssertEqual(session.viewVisits[0].errorEvents.count, 0)
        XCTAssertEqual(session.viewVisits[0].longTaskEvents.count, 0)
    }

    // MARK: - Integration with Crash Reporting

    func testGivenRegisteredCrashReporter_whenRUMViewEventIsSend_itIsUpdatedInCurrentCrashContext() throws {
        let randomUserInfoAttributes = mockRandomAttributes()
        let randomViewEventAttributes = mockRandomAttributes()

        core.context = .mockWith(
            userInfo: .init(
                id: .mockRandom(),
                name: .mockRandom(),
                email: .mockRandom(),
                extraInfo: randomUserInfoAttributes
            )
        )

        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        // Given
        let crashReporter = try XCTUnwrap(
            CrashReporter(
                core: core,
                configuration: .mockAny()
            )
        )

        try core.register(integration: crashReporter)

        // When
        let monitor = try createTestableRUMMonitor()
        monitor.startView(viewController: mockView, attributes: randomViewEventAttributes)

        // Then
        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers().filterApplicationLaunchView()
        let lastRUMViewEventSent: RUMViewEvent = try rumEventMatchers[0].model()

        let currentLastRUMViewEventSent = try XCTUnwrap(crashReporter.crashContextProvider.currentCrashContext?.lastRUMViewEvent)
        DDAssertJSONEqual(currentLastRUMViewEventSent, lastRUMViewEventSent)
    }

    // MARK: - Thread safety

    func testRandomlyCallingDifferentAPIsConcurrentlyDoesNotCrash() {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        let monitor = RUMMonitor.initialize(in: core)
        let view = mockView

        DispatchQueue.concurrentPerform(iterations: 900) { iteration in
            let modulo = iteration % 14

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
            case 11: monitor.addAttribute(forKey: String.mockRandom(), value: String.mockRandom())
            case 12: monitor.removeAttribute(forKey: String.mockRandom())
            case 13: monitor.dd.enableRUMDebugging(.random())
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
        let core = NOPDatadogCore()

        // when
        let monitor = RUMMonitor.initialize(in: core)

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `Datadog.initialize()` must be called prior to `RUMMonitor.initialize()`."
        )
        XCTAssertTrue(monitor is DDNoopRUMMonitor)
    }

    func testGivenRUMFeatureDisabled_whenInitializingRUMMonitor_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        XCTAssertNil(core.feature(RUMFeature.self))

        // when
        let monitor = RUMMonitor.initialize(in: core)

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            "🔥 Datadog SDK usage error: `RUMMonitor.initialize()` produces a non-functional monitor, as the RUM feature is disabled."
        )
        XCTAssertTrue(monitor is DDNoopRUMMonitor)
    }

    func testGivenRUMMonitorInitialized_whenInitializingAnotherTime_itPrintsError() {
        let printFunction = PrintFunctionMock()
        consolePrint = printFunction.print
        defer { consolePrint = { print($0) } }

        // given
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        Global.rum = RUMMonitor.initialize(in: core)
        defer { Global.rum = DDNoopRUMMonitor() }

        // when
        _ = RUMMonitor.initialize(in: core)

        // then
        XCTAssertEqual(
            printFunction.printedMessage,
            """
            🔥 Datadog SDK usage error: The `RUMMonitor` instance was already created. Use existing `Global.rum` instead of initializing the `RUMMonitor` another time.
            """
        )
    }

    func testGivenRUMMonitorInitialized_whenTogglingDatadogDebugRUM_itTogglesRUMDebugging() {
        // given
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        Global.rum = RUMMonitor.initialize(in: core)
        defer { Global.rum = DDNoopRUMMonitor() }

        let monitor = Global.rum.dd
        monitor.flush()
        XCTAssertNil(monitor.debugging)

        // when & then
        Datadog.debugRUM = true
        monitor.flush()
        XCTAssertNotNil(monitor.debugging)

        Datadog.debugRUM = false
        monitor.flush()
        XCTAssertNil(monitor.debugging)
    }

    func testGivenRUMAutoInstrumentationEnabled_whenRUMMonitorIsNotRegistered_itPrintsWarningsOnEachEvent() throws {
        Datadog.initialize(
            appContext: .mockAny(),
            trackingConsent: .mockRandom(),
            configuration: Datadog.Configuration
                .builderUsing(rumApplicationID: .mockAny(), clientToken: .mockAny(), environment: .mockAny())
                .trackURLSession(firstPartyHosts: [.mockAny()])
                .trackUIKitRUMViews(using: UIKitRUMViewsPredicateMock(result: .init(name: .mockAny())))
                .trackUIKitRUMActions()
                .build()
        )
        defer { Datadog.flushAndDeinitialize() }

        let dd = DD.mockWith(logger: CoreLoggerMock())
        defer { dd.reset() }

        // Given
        let urlInstrumentation = try XCTUnwrap(defaultDatadogCore.v1.feature(URLSessionAutoInstrumentation.self))
        let resourcesHandler = urlInstrumentation.interceptor.handler
        let rumInstrumentation = try XCTUnwrap(defaultDatadogCore.v1.feature(RUMInstrumentation.self))
        let viewsHandler = rumInstrumentation.viewsHandler
        let userActionsHandler = try XCTUnwrap(rumInstrumentation.userActionsAutoInstrumentation?.handler)

        // When
        XCTAssertTrue(Global.rum is DDNoopRUMMonitor)

        // Then
        resourcesHandler.notify_taskInterceptionCompleted(interception: TaskInterception(request: .mockAny(), isFirstParty: .mockAny()))
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            RUM Resource was completed, but no `RUMMonitor` is registered on `Global.rum`. RUM auto instrumentation will not work.
            Make sure `Global.rum = RUMMonitor.initialize()` is called before any network request is send.
            """
        )

        viewsHandler.notify_viewDidAppear(viewController: mockView, animated: .mockAny())
        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            RUM View was started, but no `RUMMonitor` is registered on `Global.rum`. RUM instrumentation will not work.
            Make sure `Global.rum = RUMMonitor.initialize()` is called before any view appears.
            """
        )

        let mockWindow = UIWindow(frame: .zero)
        let mockUIControl = UIControl()
        mockWindow.addSubview(mockUIControl)

        userActionsHandler.notify_sendEvent(
            application: .shared,
            event: .mockWith(touch: .mockWith(view: mockUIControl))
        )

        userActionsHandler.notify_sendEvent(
            application: .shared,
            event: .mockWith(press: .mockWith(view: mockUIControl))
        )

        XCTAssertEqual(
            dd.logger.warnLog?.message,
            """
            RUM Action was detected, but no `RUMMonitor` is registered on `Global.rum`. RUM auto instrumentation will not work.
            Make sure `Global.rum = RUMMonitor.initialize()` is called before any action happens.
            """
        )
    }

    func testSendingUserActionEvents_whenGlobalAttributesHaveConflict() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        // given
        let monitor = try createTestableRUMMonitor()
        monitor.addAttribute(forKey: "abc", value: "123")

        // when
        monitor.startView(key: "View", name: nil, attributes: [:])
        monitor.addUserAction(type: .custom, name: "action1", attributes: ["abc": "456"])

        monitor.startResourceLoading(resourceKey: "/resource1", url: URL(string: "https://foo.com/1")!, attributes: ["abc": "456"])
        monitor.stopResourceLoading(resourceKey: "/resource1", response: .mockAny(), size: nil, attributes: ["abc": "789", "def": "789"])

        monitor.stopView(key: "View", attributes: [:])

        // then
        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let viewEvents = rumEventMatchers.filterRUMEvents(ofType: RUMViewEvent.self) { event in
            return event.view.name != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
        }
        XCTAssertEqual(viewEvents.count, 4)
        XCTAssertEqual(try viewEvents[0].attribute(forKeyPath: "context.abc"), "123")
        XCTAssertEqual(try viewEvents[1].attribute(forKeyPath: "context.abc"), "123")
        XCTAssertEqual(try viewEvents[2].attribute(forKeyPath: "context.abc"), "123")
        XCTAssertEqual(try viewEvents[3].attribute(forKeyPath: "context.abc"), "123")

        let actionEvents = rumEventMatchers.filterRUMEvents(ofType: RUMActionEvent.self) { event in
            return event.view.name != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
        }
        XCTAssertEqual(actionEvents.count, 1)
        XCTAssertEqual(try actionEvents[0].attribute(forKeyPath: "context.abc"), "456")

        let resourceEvents = rumEventMatchers.filterRUMEvents(ofType: RUMResourceEvent.self) { event in
            return event.view.name != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
        }
        XCTAssertEqual(resourceEvents.count, 1)
        XCTAssertEqual(try resourceEvents[0].attribute(forKeyPath: "context.abc"), "789")
        XCTAssertEqual(try resourceEvents[0].attribute(forKeyPath: "context.def"), "789")
    }

    func testSendingUserActionEvents_whenViewAttributesHaveConflict() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        // given
        let monitor = try createTestableRUMMonitor()
        monitor.startView(key: "View", name: nil, attributes: ["abc": "123"])

        // when
        monitor.addUserAction(type: .custom, name: "action1", attributes: ["abc": "456"])

        monitor.startResourceLoading(resourceKey: "/resource1", url: URL(string: "https://foo.com/1")!, attributes: ["abc": "456"])
        monitor.stopResourceLoading(resourceKey: "/resource1", response: .mockAny(), size: nil, attributes: ["abc": "789", "def": "789"])

        monitor.stopView(key: "View", attributes: [:])

        // then
        let rumEventMatchers = try core.waitAndReturnRUMEventMatchers()

        let viewEvents = rumEventMatchers.filterRUMEvents(ofType: RUMViewEvent.self) { event in
            return event.view.name != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
        }
        XCTAssertEqual(viewEvents.count, 4)
        XCTAssertEqual(try viewEvents[0].attribute(forKeyPath: "context.abc"), "123")
        XCTAssertEqual(try viewEvents[1].attribute(forKeyPath: "context.abc"), "123")
        XCTAssertEqual(try viewEvents[2].attribute(forKeyPath: "context.abc"), "123")
        XCTAssertEqual(try viewEvents[3].attribute(forKeyPath: "context.abc"), "123")

        let actionEvents = rumEventMatchers.filterRUMEvents(ofType: RUMActionEvent.self) { event in
            return event.view.name != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
        }
        XCTAssertEqual(actionEvents.count, 1)
        XCTAssertEqual(try actionEvents[0].attribute(forKeyPath: "context.abc"), "456")

        let resourceEvents = rumEventMatchers.filterRUMEvents(ofType: RUMResourceEvent.self) { event in
            return event.view.name != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
        }
        XCTAssertEqual(resourceEvents.count, 1)
        XCTAssertEqual(try resourceEvents[0].attribute(forKeyPath: "context.abc"), "789")
        XCTAssertEqual(try resourceEvents[0].attribute(forKeyPath: "context.def"), "789")
    }

    // MARK: - Internal attributes

    func testHandlingInternalTimestampAttribute() throws {
        let rum: RUMFeature = .mockAny()
        core.register(feature: rum)

        var mockCommand = RUMCommandMock()
        mockCommand.attributes = [
            CrossPlatformAttributes.timestampInMilliseconds: Int64(1_000)
        ]

        let monitor = try XCTUnwrap(RUMMonitor.initialize(in: core) as? RUMMonitor)

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
            // Application Start/Launch happens too early to have attributes set.
            if (try? matcher.attribute(forKeyPath: "action.type")) == "application_start" ||
               (try? matcher.attribute(forKeyPath: "view.name")) == "ApplicationLaunch"{
                continue
            }
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

    func testWhenInitialized_itDefaultsToNative() {
        XCTAssertEqual(
            RUMResourceType(request: .mockWith(httpMethod: "POST".randomcased())), .native
        )
        XCTAssertEqual(
            RUMResourceType(request: .mockWith(httpMethod: "PUT".randomcased())), .native
        )
        XCTAssertEqual(
            RUMResourceType(request: .mockWith(httpMethod: "DELETE".randomcased())), .native
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

    func testWhenInitializingFromHTTPURLResponseWithUnknownType_itDefaultsToNative() {
        XCTAssertEqual(
            RUMResourceType(response: .mockWith(mimeType: "unknown/type")), .native
        )
    }

    func testWhenInitializingFromHTTPURLResponseWithNoType_itDefaultsToNative() {
        XCTAssertEqual(
            RUMResourceType(response: .mockWith(mimeType: nil)), .native
        )
    }
}
