/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
import UIKit
@testable import Datadog

private class ViewControllerMock: UIViewController {}

class RUMViewScopeTests: XCTestCase {
    private let output = RUMEventOutputMock()
    private let view = ViewControllerMock()
    private let parent = RUMScopeMock()
    private lazy var dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)

    func testWhenInitialViewIsStarted_itSendsApplicationStartAction() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: view,
            attributes: [:],
            startTime: currentTime
        )

        XCTAssertTrue(scope.process(command: .startInitialView(id: view, attributes: ["foo": "bar"], time: currentTime)))

        let event = try output.first(ofType: RUMEvent<RUMActionEvent>.self)
        XCTAssertEqual(event.model.date, currentTime.timeIntervalSince1970.toMilliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toString)
        XCTAssertEqual(event.model.session.type, "user")
        XCTAssertValidRumUUID(event.model.view.id)
        XCTAssertEqual(event.model.view.url, "ViewControllerMock")
        XCTAssertValidRumUUID(event.model.action.id)
        XCTAssertEqual(event.model.action.type, "application_start")
        XCTAssertNil(event.attributes)
        XCTAssertEqual(event.userInfo, dependencies.eventBuilder.userInfoProvider.value)
        XCTAssertEqual(event.networkConnectionInfo, dependencies.eventBuilder.networkConnectionInfoProvider?.current)
        XCTAssertEqual(event.mobileCarrierInfo, dependencies.eventBuilder.carrierInfoProvider?.current)
    }

    func testWhenInitialViewIsStarted_itSendsViewUpdateEvent() throws {
        let currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMViewScope(
            parent: parent,
            dependencies: dependencies,
            identity: view,
            attributes: [:],
            startTime: currentTime
        )

        XCTAssertTrue(scope.process(command: .startInitialView(id: view, attributes: ["foo": "bar"], time: currentTime)))

        let event = try output.first(ofType: RUMEvent<RUMViewEvent>.self)
        XCTAssertEqual(event.model.date, currentTime.timeIntervalSince1970.toMilliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toString)
        XCTAssertEqual(event.model.session.type, "user")
        XCTAssertValidRumUUID(event.model.view.id)
        XCTAssertEqual(event.model.view.url, "ViewControllerMock")
        XCTAssertEqual(event.model.view.timeSpent, 0)
        XCTAssertEqual(event.model.view.action.count, 1)
        XCTAssertEqual(event.model.view.error.count, 0)
        XCTAssertEqual(event.model.view.resource.count, 0)
        XCTAssertEqual(event.model.dd.documentVersion, 1)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.userInfo, dependencies.eventBuilder.userInfoProvider.value)
        XCTAssertEqual(event.networkConnectionInfo, dependencies.eventBuilder.networkConnectionInfoProvider?.current)
        XCTAssertEqual(event.mobileCarrierInfo, dependencies.eventBuilder.carrierInfoProvider?.current)
    }
}
