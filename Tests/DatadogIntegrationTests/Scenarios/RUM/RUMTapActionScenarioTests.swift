/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import HTTPServerMock
import XCTest

private extension ExampleApplication {
    func tapNoOpButton() {
        buttons["No-op Button"].tap()
    }

    func tapShowUITableView() {
        buttons["Show UITableView"].tap()
    }

    func tapTableViewItem(atIndex index: Int) {
        tables.staticTexts["Item \(index)"].tap()
    }

    func tapShowUICollectionView() {
        buttons["Show UICollectionView"].tap()
    }

    func tapCollectionViewItem(atIndex index: Int) {
        collectionViews.staticTexts["Item \(index)"].tap()
    }

    func tapShowVariousUIControls() {
        buttons["Show various UIControls"].tap()
    }

    func tapTextField() {
        tables.cells
            .containing(.staticText, identifier: "UITextField")
            .children(matching: .textField).element
            .tap()
    }

    func enterTextUsingKeyboard(_ text: String) {
        text.forEach { letter in
            keys[String(letter)].tap()
        }
    }

    func dismissKeyboard() {
        // tap in the middle of the screen
        coordinate(withNormalizedOffset: .init(dx: 0.5, dy: 0.5))
            .tap()
    }

    func tapStepperPlusButton() {
        tables.buttons["Increment"].tap()
    }

    func moveSlider(to position: CGFloat) {
        tables.sliders["50%"].adjust(toNormalizedSliderPosition: position)
    }

    func tapSegmentedControlSegment(label: String) {
        tables.buttons[label].tap()
    }

    func tapNavigationBarButton(named barButtonIdentifier: String) {
        navigationBars["Example.RUMTASVariousUIControllsView"]
            .buttons[barButtonIdentifier]
            .tap()
    }
}

class RUMTapActionScenarioTests: IntegrationTests, RUMCommonAsserts {
    func testRUMTapActionScenario() throws {
        // Server session recording RUM events send to `HTTPServerMock`.
        let rumServerSession = server.obtainUniqueRecordingSession()

        let app = ExampleApplication()
        app.launchWith(
            testScenario: RUMTapActionScenario.self,
            rumEndpointURL: rumServerSession.recordingURL
        )

        app.tapNoOpButton()
        app.tapShowUITableView()
        app.tapTableViewItem(atIndex: 4)
        app.tapShowUICollectionView()
        app.tapCollectionViewItem(atIndex: 14)
        app.tapShowVariousUIControls()
        app.tapTextField()
        app.enterTextUsingKeyboard("foo")
        app.dismissKeyboard()
        app.tapStepperPlusButton()
        app.moveSlider(to: 0.25)
        app.tapSegmentedControlSegment(label: "B")
        app.tapNavigationBarButton(named: "Search")
        app.tapNavigationBarButton(named: "Share")
        app.tapNavigationBarButton(named: "Back")

        // Get POST requests
        let recordedRUMRequests = try rumServerSession
            .pullRecordedPOSTRequests(count: 2, timeout: dataDeliveryTimeout)

        // Get RUM Events
        let rumEventsMatchers = try recordedRUMRequests
            .flatMap { request in try RUMEventMatcher.fromNewlineSeparatedJSONObjectsData(request.httpBody) }

        // Assert common things
        assertHTTPHeadersAndPath(in: recordedRUMRequests)

        // Get RUM Sessions
        let rumSessions = try RUMSessionMatcher.groupMatchersBySessions(rumEventsMatchers)
        XCTAssertEqual(rumSessions.count, 1, "All events should be tracked within one RUM Session.")

        let session = rumSessions[0]
        XCTAssertEqual(session.viewVisits.count, 7, "The RUM Session should track 8 RUM Views")

        XCTAssertEqual(session.viewVisits[0].path, "MenuViewController")
        XCTAssertEqual(session.viewVisits[0].actionEvents.count, 3)
        XCTAssertEqual(session.viewVisits[0].actionEvents[0].action.type, .applicationStart)
        XCTAssertEqual(session.viewVisits[0].actionEvents[1].action.target?.name, "UIButton")
        XCTAssertEqual(session.viewVisits[0].actionEvents[2].action.target?.name, "UIButton(Show UITableView)")

        XCTAssertEqual(session.viewVisits[1].path, "TableViewController")
        XCTAssertEqual(session.viewVisits[1].actionEvents.count, 1)
        XCTAssertEqual(
            session.viewVisits[1].actionEvents[0].action.target?.name,
            "UITableViewCell(Item 4)"
        )

        XCTAssertEqual(session.viewVisits[2].path, "MenuViewController")
        XCTAssertEqual(session.viewVisits[2].actionEvents.count, 1)
        XCTAssertEqual(session.viewVisits[2].actionEvents[0].action.target?.name, "UIButton(Show UICollectionView)")

        XCTAssertEqual(session.viewVisits[3].path, "CollectionViewController")
        XCTAssertEqual(session.viewVisits[3].actionEvents.count, 1)
        XCTAssertEqual(
            session.viewVisits[3].actionEvents[0].action.target?.name,
            "Example.RUMTASCollectionViewCell(Item 14)"
        )

        XCTAssertEqual(session.viewVisits[4].path, "MenuViewController")
        XCTAssertEqual(session.viewVisits[4].actionEvents.count, 1)
        XCTAssertEqual(session.viewVisits[4].actionEvents[0].action.target?.name, "UIButton(Show various UIControls)")

        XCTAssertEqual(session.viewVisits[5].path, "UIControlsViewController")
        XCTAssertEqual(session.viewVisits[5].actionEvents.count, 7)
        XCTAssertEqual(session.viewVisits[5].actionEvents[0].action.target?.name, "UITextField")
        XCTAssertEqual(session.viewVisits[5].actionEvents[1].action.target?.name, "UIStepper")
        XCTAssertEqual(session.viewVisits[5].actionEvents[2].action.target?.name, "UISlider")
        XCTAssertEqual(session.viewVisits[5].actionEvents[3].action.target?.name, "UISegmentedControl")
        XCTAssertEqual(session.viewVisits[5].actionEvents[4].action.target?.name, "_UIButtonBarButton(Search)")
        XCTAssertEqual(session.viewVisits[5].actionEvents[5].action.target?.name, "_UIButtonBarButton(Share)")
        XCTAssertEqual(session.viewVisits[5].actionEvents[6].action.target?.name, "_UIButtonBarButton") // back button

        XCTAssertEqual(session.viewVisits[6].path, "MenuViewController")
        XCTAssertEqual(session.viewVisits[6].actionEvents.count, 0)
    }
}
