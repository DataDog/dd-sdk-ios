/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class RUMResourceScopeTests: XCTestCase {
    private let output = RUMEventOutputMock()
    private lazy var dependencies: RUMScopeDependencies = .mockWith(eventOutput: output)
    private let parent = RUMScopeMock(
        context: .mockWith(
            rumApplicationID: "rum-123",
            sessionID: .mockRandom(),
            activeViewID: .mockRandom(),
            activeViewURI: "FooViewController",
            activeUserActionID: .mockRandom()
        )
    )

    func testDefaultContext() {
        let scope = RUMResourceScope(
            parent: parent,
            dependencies: .mockAny(),
            resourceName: .mockAny(),
            attributes: [:],
            startTime: .mockAny(),
            url: .mockAny(),
            httpMethod: .mockAny()
        )

        XCTAssertEqual(scope.context.rumApplicationID, parent.context.rumApplicationID)
        XCTAssertEqual(scope.context.sessionID, parent.context.sessionID)
        XCTAssertEqual(scope.context.activeViewID, try XCTUnwrap(parent.context.activeViewID))
        XCTAssertEqual(scope.context.activeViewURI, try XCTUnwrap(parent.context.activeViewURI))
        XCTAssertEqual(scope.context.activeUserActionID, try XCTUnwrap(parent.context.activeUserActionID))
    }

    func testWhenResourceLoadingEnds_itSendsResourceEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMResourceScope(
            parent: parent,
            dependencies: dependencies,
            resourceName: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: "POST"
        )

        currentTime.addTimeInterval(2)

        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceCommand(
                    resourceName: "/resource/1",
                    time: currentTime,
                    attributes: ["foo": "bar"],
                    type: "image",
                    httpStatusCode: 200,
                    size: 1_024
                )
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMResourceEvent>.self).first)
        XCTAssertEqual(event.model.date, Date.mockDecember15th2019At10AMUTC().timeIntervalSince1970.toMilliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toString)
        XCTAssertEqual(event.model.session.type, "user")
        XCTAssertEqual(event.model.view.id, parent.context.activeViewID?.toString)
        XCTAssertEqual(event.model.view.url, "FooViewController")
        XCTAssertEqual(event.model.resource.type, "image")
        XCTAssertEqual(event.model.resource.url, "https://foo.com/resource/1")
        XCTAssertEqual(event.model.resource.statusCode, 200)
        XCTAssertEqual(event.model.resource.duration, 2_000_000_000)
        XCTAssertEqual(event.model.resource.size, 1_024)
        XCTAssertEqual(try XCTUnwrap(event.model.action?.id), parent.context.activeUserActionID?.toString)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.userInfo, dependencies.eventBuilder.userInfoProvider.value)
        XCTAssertEqual(event.networkConnectionInfo, dependencies.eventBuilder.networkConnectionInfoProvider?.current)
        XCTAssertEqual(event.mobileCarrierInfo, dependencies.eventBuilder.carrierInfoProvider?.current)
    }

    func testWhenResourceLoadingEndsWithError_itSendsErrorEvent() throws {
        var currentTime: Date = .mockDecember15th2019At10AMUTC()
        let scope = RUMResourceScope(
            parent: parent,
            dependencies: dependencies,
            resourceName: "/resource/1",
            attributes: [:],
            startTime: currentTime,
            url: "https://foo.com/resource/1",
            httpMethod: "POST"
        )

        currentTime.addTimeInterval(2)

        XCTAssertFalse(
            scope.process(
                command: RUMStopResourceWithErrorCommand(
                    resourceName: "/resource/1",
                    time: currentTime,
                    attributes: ["foo": "bar"],
                    errorMessage: "error message",
                    errorSource: "network",
                    httpStatusCode: 404
                )
            )
        )

        let event = try XCTUnwrap(output.recordedEvents(ofType: RUMEvent<RUMErrorEvent>.self).first)
        XCTAssertEqual(event.model.date, currentTime.timeIntervalSince1970.toMilliseconds)
        XCTAssertEqual(event.model.application.id, scope.context.rumApplicationID)
        XCTAssertEqual(event.model.session.id, scope.context.sessionID.toString)
        XCTAssertEqual(event.model.session.type, "user")
        XCTAssertEqual(event.model.view.id, parent.context.activeViewID?.toString)
        XCTAssertEqual(event.model.view.url, "FooViewController")
        XCTAssertEqual(event.model.error.message, "error message")
        XCTAssertEqual(event.model.error.source, "network")
        XCTAssertEqual(event.model.error.resource?.method, "POST")
        XCTAssertEqual(event.model.error.resource?.statusCode, 404)
        XCTAssertEqual(event.model.error.resource?.url, "https://foo.com/resource/1")
        XCTAssertEqual(try XCTUnwrap(event.model.action?.id), parent.context.activeUserActionID?.toString)
        XCTAssertEqual(event.attributes as? [String: String], ["foo": "bar"])
        XCTAssertEqual(event.userInfo, dependencies.eventBuilder.userInfoProvider.value)
        XCTAssertEqual(event.networkConnectionInfo, dependencies.eventBuilder.networkConnectionInfoProvider?.current)
        XCTAssertEqual(event.mobileCarrierInfo, dependencies.eventBuilder.carrierInfoProvider?.current)
    }
}
