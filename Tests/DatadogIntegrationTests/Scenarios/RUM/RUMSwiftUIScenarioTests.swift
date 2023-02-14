/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest

private extension ExampleApplication {
    func tapTapBar(item name: String) {
        tabBars.buttons[name].safeTap()
    }

    func tapPushToNextView() {
        buttons["Push to Next View"].safeTap(within: 10)
    }

    func tapPresentModalView() {
        buttons["Present Modal View"].safeTap(within: 10)
    }

    func tapBackButton(to index: Int) {
        buttons["Screen \(index)"].safeTap(within: 10)
    }

    func swipeRightInteraction() {
        let coordinate1 = coordinate(withNormalizedOffset: .init(dx: 0, dy: 0.5))
        let coordinate2 = coordinate(withNormalizedOffset: .init(dx: 0.80, dy: 0.5))
        coordinate1.press(forDuration: 0.5, thenDragTo: coordinate2)
    }

    func swipeDownInteraction() {
        let coordinate1 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.2))
        let coordinate2 = coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.8))
        coordinate1.press(forDuration: 0.5, thenDragTo: coordinate2)
    }
}

class RUMSwiftUIScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testSwiftUIScenario() throws {
        guard #available(iOS 13, *) else {
            return
        }

        // Server session recording RUM events send to `HTTPServerMock`.
        let recording = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMSwiftUIInstrumentationScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: recording.recordingURL
            )
        )

        // start on "SwiftUI.View 1"
        app.tapPushToNextView() // go to "SwiftUI.View 2"
        app.tapPushToNextView() // go to "SwiftUI.View 3"
        app.tapPresentModalView() // go to "SwiftUI.View 4"
        app.swipeDownInteraction() // go to "SwiftUI.View 3"
        app.tapTapBar(item: "Screen 100") // go to "SwiftUI.View 100"
        app.tapPresentModalView() // go to "SwiftUI.View 101"
        app.swipeDownInteraction() // go back to "SwiftUI.View 100"
        app.tapTapBar(item: "Navigation View") // go to "SwiftUI.View 3"

        try app.endRUMSession()

        // Get RUM Sessions with expected number of View visits
        let requests = try recording.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: requests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: requests))
        sendCIAppLog(session)

        let applicationLaunchView = try XCTUnwrap(session.applicationLaunchView)
        XCTAssertEqual(applicationLaunchView.actionEvents[0].action.type, .applicationStart)
        XCTAssertGreaterThan(applicationLaunchView.actionEvents[0].action.loadingTime!, 0)

        let visits = session.viewVisits
        XCTAssertEqual(visits[0].name, "SwiftUI View 1")
        XCTAssertTrue(visits[0].path.matches(regex: "SwiftUI View 1\\/[0-9]*"))
        XCTAssertEqual(visits[0].actionEvents[0].action.target?.name, "Tap Push to Next View")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[0]) // go to "Screen 2"

        XCTAssertEqual(visits[1].name, "SwiftUI View 2")
        XCTAssertTrue(visits[1].path.matches(regex: "SwiftUI View 2\\/[0-9]*"))
        XCTAssertEqual(visits[1].actionEvents[0].action.target?.name, "Tap Push to Next View")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[1])// go to "Screen 3"

        XCTAssertEqual(visits[2].name, "SwiftUI View 3")
        XCTAssertTrue(visits[2].path.matches(regex: "SwiftUI View 3\\/[0-9]*"))
        XCTAssertEqual(visits[2].actionEvents[0].action.target?.name, "Tap Modal View")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[2])// go to "Screen 4"

        XCTAssertEqual(visits[3].name, "UIKit View 4")
        XCTAssertEqual(visits[3].path, "Example.UIScreenViewController")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[3])// go to "Screen 3"

        XCTAssertEqual(visits[4].name, "SwiftUI View 3")
        XCTAssertTrue(visits[4].path.matches(regex: "SwiftUI View 3\\/[0-9]*"))
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[4])// go to "Screen 100"

        XCTAssertEqual(visits[5].name, "SwiftUI View 100")
        XCTAssertTrue(visits[5].path.matches(regex: "SwiftUI View 100\\/[0-9]*"))
        XCTAssertEqual(visits[5].actionEvents[0].action.target?.name, "Tap Modal View")
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[5])// go to "Screen 101"

        XCTAssertEqual(visits[6].name, "SwiftUI View 101")
        XCTAssertTrue(visits[6].path.matches(regex: "SwiftUI View 101\\/[0-9]*"))
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[6])// go to "Screen 100"

        XCTAssertEqual(visits[7].name, "SwiftUI View 100")
        XCTAssertTrue(visits[7].path.matches(regex: "SwiftUI View 100\\/[0-9]*"))
        RUMSessionMatcher.assertViewWasEventuallyInactive(visits[7])// go to "Screen 3"

        XCTAssertEqual(visits[8].name, "SwiftUI View 3")
        XCTAssertTrue(visits[8].path.matches(regex: "SwiftUI View 3\\/[0-9]*"))
    }
}
