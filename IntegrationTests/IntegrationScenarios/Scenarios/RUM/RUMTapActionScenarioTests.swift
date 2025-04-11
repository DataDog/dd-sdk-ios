/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import HTTPServerMock
import TestUtilities
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

    func tapTextField(_ text: String) {
        let textField = tables.cells
            .containing(.staticText, identifier: "UITextField")
            .children(matching: .textField).element
        textField.tap()
        textField.typeText(text)
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
        tables.sliders.firstMatch.adjust(toNormalizedSliderPosition: position)
    }

    func tapSegmentedControlSegment(label: String) {
        tables.buttons[label].tap()
    }

    func tapNavigationBarButton(named barButtonIdentifier: String) {
        navigationBars["Runner.RUMTASVariousUIControllsView"]
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
            testScenarioClassName: "RUMTapActionScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: rumServerSession.recordingURL
            )
        )

        app.tapNoOpButton()
        app.tapShowUITableView()
        app.tapTableViewItem(atIndex: 4)
        app.tapShowUICollectionView()
        app.tapCollectionViewItem(atIndex: 14)
        app.tapShowVariousUIControls()
        app.tapTextField("foo")
        app.dismissKeyboard()
        app.tapStepperPlusButton()
        app.moveSlider(to: 0.25)
        app.tapSegmentedControlSegment(label: "B")
        app.tapNavigationBarButton(named: "Search")
        app.tapNavigationBarButton(named: "Share")
        app.tapNavigationBarButton(named: "Back")

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

        XCTAssertEqual(session.views[1].name, "MenuView")
        XCTAssertEqual(session.views[1].path, "Runner.RUMTASScreen1ViewController")
        XCTAssertEqual(session.views[1].actionEvents.count, 2)
        XCTAssertEqual(session.views[1].actionEvents[0].action.target?.name, "UIButton")
        XCTAssertEqual(session.views[1].actionEvents[1].action.target?.name, "UIButton(Show UITableView)")

        XCTAssertEqual(session.views[2].name, "TableView")
        XCTAssertEqual(session.views[2].path, "Runner.RUMTASTableViewController")
        XCTAssertEqual(session.views[2].actionEvents.count, 1)
        XCTAssertEqual(
            session.views[2].actionEvents[0].action.target?.name,
            "UITableViewCell(Item 4)"
        )

        XCTAssertEqual(session.views[3].name, "MenuView")
        XCTAssertEqual(session.views[3].path, "Runner.RUMTASScreen1ViewController")
        XCTAssertEqual(session.views[3].actionEvents.count, 1)
        XCTAssertEqual(session.views[3].actionEvents[0].action.target?.name, "UIButton(Show UICollectionView)")

        XCTAssertEqual(session.views[4].name, "CollectionView")
        XCTAssertEqual(session.views[4].path, "Runner.RUMTASCollectionViewController")
        XCTAssertEqual(session.views[4].actionEvents.count, 1)
        XCTAssertEqual(
            session.views[4].actionEvents[0].action.target?.name,
            "Runner.RUMTASCollectionViewCell(Item 14)"
        )

        XCTAssertEqual(session.views[5].name, "MenuView")
        XCTAssertEqual(session.views[5].path, "Runner.RUMTASScreen1ViewController")
        XCTAssertEqual(session.views[5].actionEvents.count, 1)
        XCTAssertEqual(session.views[5].actionEvents[0].action.target?.name, "UIButton(Show various UIControls)")

        XCTAssertEqual(session.views[6].name, "UIControlsView")
        XCTAssertEqual(session.views[6].path, "Runner.RUMTASVariousUIControllsViewController")
        XCTAssertEqual(session.views[6].actionEvents.count, 7)
        let targetNames = session.views[6].actionEvents.compactMap { $0.action.target?.name }
        XCTAssertEqual(targetNames[0], "UITextField")
        XCTAssertEqual(targetNames[1], "UIStepper")
        XCTAssertEqual(targetNames[2], "UISlider")
        XCTAssertEqual(targetNames[3], "UISegmentedControl")
        XCTAssertEqual(targetNames[4], "_UIButtonBarButton(Search)")
        XCTAssertEqual(targetNames[5], "_UIButtonBarButton(Share)")
        XCTAssert(targetNames[6].contains("_UIButtonBarButton"), "Target name should be either _UIButtonBarButton (iOS 13) or _UIButtonBarButton(BackButton) (iOS 14)") // back button

        XCTAssertEqual(session.views[7].name, "MenuView")
        XCTAssertEqual(session.views[7].path, "Runner.RUMTASScreen1ViewController")
        XCTAssertEqual(session.views[7].actionEvents.count, 0)
    }
}
