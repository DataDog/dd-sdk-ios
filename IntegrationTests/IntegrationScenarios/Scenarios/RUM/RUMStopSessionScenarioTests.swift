// Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
// This product includes software developed at Datadog (https://www.datadoghq.com/).
// Copyright 2023-Present Datadog, Inc.

import Foundation
import XCTest

class RUMStopSessionKioskScreen: XCUIApplication {
    func tapStartSession() {
        buttons["Start Session"].tap()
    }

    func tapStartInterruptedSession() {
        buttons["Start Interrupted Session"].tap()
    }
}

class RUMSendKioskEventsScreen: XCUIApplication {
    func back() {
        navigationBars.buttons["Back"].tap()
    }

    func tapDownloadResourceAndWait() {
        buttons["Download Resource"].tap()
        _ = buttons["Done"].waitForExistence(timeout: 2)
    }
}

class RUMSendKioskEventsInterruptedScreen: XCUIApplication {
    func back() {
        navigationBars.buttons["Back"].tap()
    }

    func tapDownloadResource() {
        buttons["Download Resource"].tap()
    }
}

class RUMStopSessionScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMStopSessionScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMStopSessionsScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        let kioskScreen = RUMStopSessionKioskScreen()
        kioskScreen.tapStartSession()
        let sendEventsScreen = RUMSendKioskEventsScreen()
        sendEventsScreen.tapDownloadResourceAndWait()
        sendEventsScreen.back()

        kioskScreen.tapStartInterruptedSession()
        let sendInterruptedEventsScreen = RUMSendKioskEventsInterruptedScreen()
        sendInterruptedEventsScreen.tapDownloadResource()
        sendInterruptedEventsScreen.back()

        try app.endRUMSession()

        // Get RUM Sessions with expected number of View visits
        let recordedRUMRequests = try rumServerSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            // 4th session should only contain the test session ending
            let sessions = try RUMSessionMatcher.sessions(maxCount: 4, from: requests)
            // No active views in any session
            return sessions.count == 4 && sessions.allSatisfy { session in
                !session.viewVisits.contains(where: { $0.viewEvents.last?.view.isActive == true })
            }
        }

        assertRUM(requests: recordedRUMRequests)

        let sessions = try RUMSessionMatcher.sessions(maxCount: 4, from: recordedRUMRequests)
        do {
            let appStartSession = sessions[0]

            let launchView = try XCTUnwrap(appStartSession.applicationLaunchView)
            XCTAssertEqual(launchView.actionEvents[0].action.type, .applicationStart)

            let view1 = appStartSession.viewVisits[0]
            XCTAssertEqual(view1.name, "KioskViewController")
            XCTAssertEqual(view1.path, "Runner.KioskViewController")
            XCTAssertEqual(view1.viewEvents.last?.session.isActive, false)
            RUMSessionMatcher.assertViewWasEventuallyInactive(view1)
        }

        // Second session sends a resource and ends returning to the KioskViewController
        do {
            let normalSession = sessions[1]
            XCTAssertNil(normalSession.applicationLaunchView)

            let view1 = normalSession.viewVisits[0]
            XCTAssertTrue(try XCTUnwrap(view1.viewEvents.first?.session.isActive))
            XCTAssertEqual(view1.name, "KioskSendEvents")
            XCTAssertEqual(view1.path, "Runner.KioskSendEventsViewController")
            XCTAssertEqual(view1.resourceEvents[0].resource.url, "https://foo.com/resource/1")
            XCTAssertEqual(view1.resourceEvents[0].resource.statusCode, 200)
            XCTAssertEqual(view1.resourceEvents[0].resource.type, .image)
            XCTAssertNotNil(view1.resourceEvents[0].resource.duration)
            XCTAssertGreaterThan(view1.resourceEvents[0].resource.duration!, 100_000_000 - 1) // ~0.1s
            XCTAssertLessThan(view1.resourceEvents[0].resource.duration!, 1_000_000_000 * 30) // less than 30s (big enough to balance NTP sync)
            RUMSessionMatcher.assertViewWasEventuallyInactive(view1)

            let view2 = normalSession.viewVisits[1]
            XCTAssertEqual(view2.name, "KioskViewController")
            XCTAssertEqual(view2.path, "Runner.KioskViewController")
            XCTAssertEqual(view2.viewEvents.last?.session.isActive, false)
            RUMSessionMatcher.assertViewWasEventuallyInactive(view2)
        }

        // Third session, same as the first but longer before completing resources
        do {
            let interruptedSession = sessions[2]
            XCTAssertNil(interruptedSession.applicationLaunchView)

            let view1 = interruptedSession.viewVisits[0]
            XCTAssertTrue(try XCTUnwrap(view1.viewEvents.first?.session.isActive))
            XCTAssertEqual(view1.name, "KioskSendInterruptedEvents")
            XCTAssertEqual(view1.path, "Runner.KioskSendInterruptedEventsViewController")
            XCTAssertEqual(view1.resourceEvents[0].resource.url, "https://foo.com/resource/1")
            XCTAssertEqual(view1.resourceEvents[0].resource.statusCode, 200)
            XCTAssertEqual(view1.resourceEvents[0].resource.type, .image)
            XCTAssertNotNil(view1.resourceEvents[0].resource.duration)
            XCTAssertGreaterThan(view1.resourceEvents[0].resource.duration!, 100_000_000 - 1) // ~0.1s
            XCTAssertLessThan(view1.resourceEvents[0].resource.duration!, 1_000_000_000 * 30) // less than 30s (big enough to balance NTP sync)
            RUMSessionMatcher.assertViewWasEventuallyInactive(view1)

            let view2 = interruptedSession.viewVisits[1]
            XCTAssertEqual(view2.name, "KioskViewController")
            XCTAssertEqual(view2.path, "Runner.KioskViewController")
            XCTAssertEqual(view2.viewEvents.last?.session.isActive, false)
            RUMSessionMatcher.assertViewWasEventuallyInactive(view2)
        }
    }
}
