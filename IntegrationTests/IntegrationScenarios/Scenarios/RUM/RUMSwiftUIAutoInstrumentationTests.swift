/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM

private extension ExampleApplication {
    func tapBackButton(_ buttonTitle: String) {
        navigationBars.buttons[buttonTitle].firstMatch.safeTap(within: 5)
    }
}

class RUMSwiftUIAutoInstrumentationTests: IntegrationTests, RUMCommonAsserts {
    // MARK: - View Tracking
    @available(iOS 16.0, *)
    func testSingleViewRoot() throws {
        let serverSession = server.obtainUniqueRecordingSession()
        let app = ExampleApplication()
        app.launchWith(
          testScenarioClassName: "RUMSwiftUIAutoInstrumentationSingleRootViewScenario",
          serverConfiguration: .init(rumEndpoint: serverSession.recordingURL)
        )

        app.tapView(named: "Item 1") // Navigate to detail
        app.tapBackButton("Navigation Stack") // Go back

        app.tapView(named: "Category 2") // Navigate to detail
        app.tapView(named: "Category 2 - Item 1") // Navigate to detail level 2
        app.tapBackButton("Back") // Go back
        app.tapBackButton("Navigation Stack") // Go back

        try app.endRUMSession()

        let requests = try serverSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            return try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: requests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: requests))
        sendCIAppLog(session)

        let initialView = session.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertEqual(initialView.actionEvents[0].action.type, .applicationStart)

        XCTAssertEqual(session.views[1].name, "NavigationStackHostingController<AnyView>")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[1])
        XCTAssertEqual(session.views[2].name, "NumberDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[2])
        XCTAssertEqual(session.views[3].name, "NavigationStackHostingController<AnyView>")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[3])

        XCTAssertEqual(session.views[4].name, "CategoryDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[4])
        XCTAssertEqual(session.views[5].name, "ItemDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[5])
        XCTAssertEqual(session.views[6].name, "CategoryDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[6])
        XCTAssertEqual(session.views[7].name, "NavigationStackHostingController<AnyView>")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[7])
    }

    @available(iOS 16.0, *)
    func testRootTabbar() throws {
        // Server session recording RUM events
        let serverSession = server.obtainUniqueRecordingSession()
        let app = ExampleApplication()
        app.launchWith(
            testScenarioClassName: "RUMSwiftUIAutoInstrumentationRootTabbarScenario",
            serverConfiguration: HTTPServerMockConfiguration(
                rumEndpoint: serverSession.recordingURL
            )
        )

        // Tab 0: Navigation View
        app.tapView(named: "Item 3") // Navigate to detail
        app.tapBackButton("Navigation View") // Go back
        app.tapView(named: "Category 1") // Navigate to detail evel 1
        app.tapView(named: "Category 1 - Item 4") // Navigate to detail level 2
        app.tapBackButton("Back") // Go back
        app.tapBackButton("Navigation View") // Go back

        // Tab 1: Navigation Stack
        app.tapTapBar(item: "Navigation Stack") // Navigate to 2nd tab
        app.tapView(named: "Category 2")// Navigate to detail
        app.tapView(named: "Category 2 - Item 1") // Navigate to detail level 2
        app.tapBackButton("Back") // Go back
        app.tapBackButton("Navigation Stack") // Go back

        // Tab 2: Navigation Split View
        app.tapTapBar(item: "Navigation Split") // Navigate to 3rd tab
        app.tapView(named: "Item 2") // Navigate to detail
        app.tapBackButton("Navigation Split") // Go back
        app.tapView(named: "Item 5") // Navigate to placeholder view
        app.tapBackButton("Navigation Split") // Go back

        // Tab 3: Modal Views
        app.tapTapBar(item: "Modals") // Navigate to 4th tab (manually isntrumented)
        app.tapButton(titled: "Show Sheet") // Show modal sheet
        app.swipeDownInteraction() // Dismiss sheet by swiping down
        app.tapButton(titled: "Show FullScreenCover") // Show modal full screen
        app.tapButton(titled: "Close") // Tap Close button

        try app.endRUMSession()

        // Get RUM Sessions
        let requests = try serverSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            return try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: requests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: requests))
        sendCIAppLog(session)

        let initialView = session.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertEqual(initialView.actionEvents[0].action.type, .applicationStart)

        // Tab 0: Navigation View
        XCTAssertEqual(session.views[1].name, "AutoTracked_HostingController_Fallback")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[1])
        XCTAssertEqual(session.views[2].name, "NumberDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[2])
        XCTAssertEqual(session.views[3].name, "AutoTracked_HostingController_Fallback")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[3])

        XCTAssertEqual(session.views[4].name, "CategoryDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[4])
        XCTAssertEqual(session.views[5].name, "ItemDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[5])
        XCTAssertEqual(session.views[6].name, "CategoryDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[6])
        XCTAssertEqual(session.views[7].name, "AutoTracked_HostingController_Fallback")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[7])

        // Tab 1: Navigation Stack
        XCTAssertEqual(session.views[8].name, "NavigationStackHostingController<AnyView>")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[8])
        XCTAssertEqual(session.views[9].name, "CategoryDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[9])
        XCTAssertEqual(session.views[10].name, "ItemDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[10])
        XCTAssertEqual(session.views[11].name, "CategoryDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[11])
        XCTAssertEqual(session.views[12].name, "NavigationStackHostingController<AnyView>")

        // Tab 2: Navigation Split
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[12])
        XCTAssertEqual(session.views[13].name, "NavigationStackHostingController<AnyView>")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[13])
        XCTAssertEqual(session.views[14].name, "NumberDetailView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[14])
        XCTAssertEqual(session.views[15].name, "NavigationStackHostingController<AnyView>")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[15])
        XCTAssertEqual(session.views[16].name, "PlaceholderView")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[16])
        XCTAssertEqual(session.views[17].name, "NavigationStackHostingController<AnyView>")

        // Tab 3: Modal Views
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[17])
        XCTAssertEqual(session.views[18].name, "Modal Tab")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[18])
        XCTAssertEqual(session.views[19].name, "ModalSheet")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[19])
        XCTAssertEqual(session.views[20].name, "Modal Tab")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[20])
        XCTAssertEqual(session.views[21].name, "ModalSheet")
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[21])
    }

    // MARK: - Action Tracking
    func testActions() throws {
        let serverSession = server.obtainUniqueRecordingSession()
        let app = ExampleApplication()
        app.launchWith(
          testScenarioClassName: "RUMSwiftUIAutoInstrumentationActionViewScenario",
          serverConfiguration: .init(rumEndpoint: serverSession.recordingURL)
        )

        app.buttons["main_button"].tap() // Button
        app.buttons["navigation-link"].tap() // Navigation Link
        app.switches["toggle"].tap() // Toggle
        app.sliders["slider"].tap() // Slider
        app.steppers["stepper"].tap() // Stepper
        app.buttons["Option 1"].tap() // Picker
        
        app.buttons["menu"].tap() // Menu
        app.buttons["menu_item_1"].tap() // Menu Item
        app.textFields["Enter text"].tap() // TextField

        try app.endRUMSession()

        let requests = try serverSession.pullRecordedRequests(timeout: dataDeliveryTimeout) { requests in
            return try RUMSessionMatcher.singleSession(from: requests)?.hasEnded() ?? false
        }

        assertRUM(requests: requests)

        let session = try XCTUnwrap(RUMSessionMatcher.singleSession(from: requests))
        sendCIAppLog(session)

        let initialView = session.views[0]
        XCTAssertTrue(initialView.isApplicationLaunchView(), "The session should start with 'application launch' view")
        XCTAssertEqual(initialView.actionEvents[0].action.type, .applicationStart)
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[0])

        let mainView = session.views[1]
        XCTAssertEqual(mainView.name, "Runner.SwiftUIAutoInstrumentationActionView")
        if #available(iOS 18.0, tvOS 18.0, visionOS 2.0, *) {
            XCTAssertEqual(mainView.actionEvents[0].action.target?.name, SwiftUIComponentNames.button)
            XCTAssertEqual(mainView.actionEvents[1].action.target?.name, SwiftUIComponentNames.navigationLink)
            XCTAssertEqual(mainView.actionEvents[2].action.target?.name, "UISwitch")
            XCTAssertEqual(mainView.actionEvents[3].action.target?.name, "UISlider(slider)")
            XCTAssertEqual(mainView.actionEvents[4].action.target?.name, "UIStepper(stepper)")
            XCTAssertEqual(mainView.actionEvents[5].action.target?.name, "UISegmentedControl")
            XCTAssertEqual(mainView.actionEvents[6].action.target?.name, "SwiftUI_Menu")
            XCTAssertEqual(mainView.actionEvents[7].action.target?.name, "_UIContextMenuCell")
            XCTAssertEqual(mainView.actionEvents[8].action.target?.name, "UITextField")
        } else {
            XCTAssertEqual(mainView.actionEvents[0].action.target?.name, SwiftUIComponentNames.unidentified)
            XCTAssertEqual(mainView.actionEvents[1].action.target?.name, SwiftUIComponentNames.unidentified)
            XCTAssertEqual(mainView.actionEvents[2].action.target?.name, "UISwitch")
            XCTAssertEqual(mainView.actionEvents[3].action.target?.name, "UISlider(slider)")
            XCTAssertEqual(mainView.actionEvents[4].action.target?.name, "UIStepper(stepper)")
            XCTAssertEqual(mainView.actionEvents[5].action.target?.name, "UISegmentedControl")
            XCTAssertEqual(mainView.actionEvents[6].action.target?.name, "SwiftUI_Menu")
            XCTAssertEqual(mainView.actionEvents[7].action.target?.name, "_UIContextMenuCell")
            XCTAssertEqual(mainView.actionEvents[8].action.target?.name, "UITextField")
        }
        RUMSessionMatcher.assertViewWasEventuallyInactive(session.views[1])
    }

    // TODO: RUM-9888 - Manual + Auto instrumentation scenario
}
