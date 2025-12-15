/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import TestUtilities
import XCTest

private extension ExampleApplication {
    func tapShowSimpleAlertButton() {
        tapButton(titled: "Show Simple Alert")
    }

    func tapShowAlertManyButtonsButton() {
        tapButton(titled: "Show Alert Many Buttons")
    }

    func tapShowAlertTextFieldsButton() {
        tapButton(titled: "Show Alert Text Field")
    }

    func tapShowSimpleActionSheetButton() {
        tapButton(titled: "Show Simple Action Sheet")
    }

    func tapShowManyButtonsActionSheet() {
        tapButton(titled: "Show Many Buttons Action Sheet")
    }

    func tapShowSwiftUIAlertView() {
        tapButton(titled: "Show SwiftUI View")
    }

    func tapAlertTextField() {
        alerts.element.textFields.firstMatch.safeTap(within: 5)
    }
}

/// Tests tracking of alerts, action sheets and confirmation dialogs.
class RUMAlertScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMAlertScenarioUIKit() throws {
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMAlertScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        app.tapShowSimpleAlertButton()
        app.tapButton(titled: "Cancel")
        app.tapShowAlertManyButtonsButton()
        app.tapButton(titled: "Delete")
        app.tapShowAlertTextFieldsButton()
        app.tapAlertTextField()
        app.typeText("Some text on text field")
        app.tapButton(titled: "OK")
        app.tapShowSimpleActionSheetButton()
        app.tapButton(titled: "OK")
        app.tapShowManyButtonsActionSheet()
        app.tapButton(titled: "Delete")

        try app.endRUMSession()

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))
        sendCIAppLog(session)

        let initialView = session.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertEqual(initialView.actionEvents[0].action.type, .applicationStart)

        XCTAssertEqual(session.views[1].path, "Runner.RUMAlertRootViewController")
        XCTAssertEqual(session.views[1].actionEvents.count, 1)

        XCTAssertEqual(session.views[2].path, "UIAlertController")
        XCTAssertEqual(session.views[2].actionEvents.count, 1)
        XCTAssertEqual(session.views[2].actionEvents[0].action.target?.name, "_UIAlertControllerActionView")

        XCTAssertEqual(session.views[3].path, "Runner.RUMAlertRootViewController")
        XCTAssertEqual(session.views[3].actionEvents.count, 1)

        XCTAssertEqual(session.views[4].path, "UIAlertController")
        XCTAssertEqual(session.views[4].actionEvents.count, 1)
        XCTAssertEqual(session.views[4].actionEvents[0].action.target?.name, "_UIAlertControllerActionView")

        XCTAssertEqual(session.views[5].path, "Runner.RUMAlertRootViewController")
        XCTAssertEqual(session.views[5].actionEvents.count, 1)

        XCTAssertEqual(session.views[6].path, "UIAlertController")
        XCTAssertEqual(session.views[6].actionEvents.count, 2)
        XCTAssertEqual(session.views[6].actionEvents[0].action.target?.name, "_UIAlertControllerTextField")
        XCTAssertEqual(session.views[6].actionEvents[1].action.target?.name, "_UIAlertControllerActionView")

        XCTAssertEqual(session.views[7].path, "Runner.RUMAlertRootViewController")
        XCTAssertEqual(session.views[7].actionEvents.count, 1)

        XCTAssertEqual(session.views[8].path, "UIAlertController")
        XCTAssertEqual(session.views[8].actionEvents.count, 1)
        XCTAssertEqual(session.views[8].actionEvents[0].action.target?.name, "_UIAlertControllerActionView")
    }

    func testRUMAlertScenarioSwiftUI() throws {
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMAlertScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        app.tapShowSwiftUIAlertView()
        app.tapShowSimpleAlertButton()
        app.tapButton(titled: "Cancel")
        app.tapShowAlertManyButtonsButton()
        app.tapButton(titled: "Delete")
        app.tapShowAlertTextFieldsButton()
        app.tapAlertTextField()
        if #available(iOS 15, tvOS 15, *) {
            app.typeText("Some text on text field")
        }
        app.tapButton(titled: "OK")
        app.tapShowSimpleActionSheetButton()
        app.tapButton(titled: "OK")
        app.tapShowManyButtonsActionSheet()
        app.tapButton(titled: "Delete")

        try app.endRUMSession()

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: recordedRUMRequests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: recordedRUMRequests))
        sendCIAppLog(session)

        let initialView = session.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertEqual(initialView.actionEvents[0].action.type, .applicationStart)

        XCTAssertEqual(session.views[1].path, "Runner.RUMAlertRootViewController")
        XCTAssertEqual(session.views[1].actionEvents.count, 1)

        XCTAssertEqual(session.views[2].path, "Runner.RUMAlertSwiftUIViewController")
        XCTAssertEqual(session.views[2].actionEvents.count, 1)

        XCTAssertEqual(session.views[3].path, "SwiftUI.PlatformAlertController")
        XCTAssertEqual(session.views[3].actionEvents.count, 1)
        XCTAssertEqual(session.views[3].actionEvents[0].action.target?.name, "_UIAlertControllerActionView")

        XCTAssertEqual(session.views[4].path, "Runner.RUMAlertSwiftUIViewController")
        XCTAssertEqual(session.views[4].actionEvents.count, 1)

        XCTAssertEqual(session.views[5].path, "SwiftUI.PlatformAlertController")
        XCTAssertEqual(session.views[5].actionEvents.count, 1)
        XCTAssertEqual(session.views[5].actionEvents[0].action.target?.name, "_UIAlertControllerActionView")

        XCTAssertEqual(session.views[6].path, "Runner.RUMAlertSwiftUIViewController")
        XCTAssertEqual(session.views[6].actionEvents.count, 1)

        XCTAssertEqual(session.views[7].path, "SwiftUI.PlatformAlertController")
        XCTAssertEqual(session.views[7].actionEvents.count, 2)
        if #available(iOS 15.0, tvOS 15.0, *) {
            XCTAssertEqual(session.views[7].actionEvents[0].action.target?.name, "_UIAlertControllerTextField")
            XCTAssertEqual(session.views[7].actionEvents[1].action.target?.name, "_UIAlertControllerActionView")
        } else {
            XCTAssertEqual(session.views[7].actionEvents[0].action.target?.name, "_UIAlertControllerActionView")
        }

        XCTAssertEqual(session.views[8].path, "Runner.RUMAlertSwiftUIViewController")
        XCTAssertEqual(session.views[8].actionEvents.count, 1)

        XCTAssertEqual(session.views[9].path, "SwiftUI.PlatformAlertController")
        XCTAssertEqual(session.views[9].actionEvents.count, 1)
        XCTAssertEqual(session.views[9].actionEvents[0].action.target?.name, "_UIAlertControllerActionView")
    }

}
