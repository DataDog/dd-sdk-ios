/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogLogs
@testable import DatadogRUM

/// Tests covering cross-feature integration between Logs and RUM: `bundleWithRumEnabled` flag,
/// `application_id`, `session_id`, `view.id`, `user_action.id` injected into recorded logs.
///
/// See `Datadog/IntegrationUnitTests/Logs/SCENARIOS.md` for the full list of scenarios this file covers.
class LogsBundlingTests: XCTestCase {
    /// Timestamp representing when the app process was spawned.
    private let processLaunchDate = Date()
    /// Simulated delay between app launch and SDK initialization (`Datadog.initialize()`).
    private let timeToSDKInit: TimeInterval = 0.7

    // MARK: - §11 RUM bundling

    func testGivenBundleWithRumEnabledAndActiveManualView_whenLogIsEmitted_logCarriesViewIdMatchingRUMSession() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.enableRUM(after: timeToSDKInit))
            .and(.startManualView(after: 0.1, viewName: "Cart"))
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("during view")
            }

        // Then
        let result = try when.then()
        let session = try result.sessions.takeSingle()
        let manualView = try XCTUnwrap(session.views.last)
        XCTAssertEqual(manualView.name, "Cart", "Expected last view to be the manual 'Cart' view (after auto-created ApplicationLaunch)")

        XCTAssertEqual(result.logs.count, 1)
        let log = result.logs[0]
        let logApplicationId: String = try log.value(forKeyPath: "application_id")
        let logSessionId: String = try log.value(forKeyPath: "session_id")
        let logViewId: String = try log.value(forKeyPath: "view.id")
        XCTAssertEqual(logApplicationId, session.applicationID, "Log application_id should match the RUM session applicationID")
        XCTAssertEqual(logSessionId, session.sessionID, "Log session_id should match the RUM session sessionID")
        XCTAssertEqual(logViewId, manualView.viewID, "Log view.id should match the active RUM view")
    }

    func testGivenBundleWithRumEnabledAndNoManualView_whenLogIsEmitted_logCarriesApplicationAndSessionIdsMatchingRUMSession() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.enableRUM(after: timeToSDKInit))
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("no manual view")
            }

        // Then
        let result = try when.then()
        let session = try result.sessions.takeSingle()
        // RUM auto-creates an ApplicationLaunch view on user launch; there is no truly view-less window in this scenario.
        let activeView = try XCTUnwrap(session.views.last)
        XCTAssertEqual(activeView.name, "ApplicationLaunch", "Expected the only active view to be the auto-created ApplicationLaunch view")

        XCTAssertEqual(result.logs.count, 1)
        let log = result.logs[0]
        let logApplicationId: String = try log.value(forKeyPath: "application_id")
        let logSessionId: String = try log.value(forKeyPath: "session_id")
        let logViewId: String = try log.value(forKeyPath: "view.id")
        XCTAssertEqual(logApplicationId, session.applicationID, "Log application_id should match the RUM session applicationID")
        XCTAssertEqual(logSessionId, session.sessionID, "Log session_id should match the RUM session sessionID")
        XCTAssertEqual(logViewId, activeView.viewID, "Log view.id should match the auto-created ApplicationLaunch view")
        log.assertNoValue(forKey: "user_action.id")
    }

    func testGivenBundleWithRumEnabledFalseAndActiveView_whenLogIsEmitted_logCarriesNoRUMContextAttributes() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.enableRUM(after: timeToSDKInit))
            .and(.startManualView(after: 0.1, viewName: "Cart"))
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.bundleWithRumEnabled = false
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.info("opted out of RUM bundling")
            }

        // Then
        let result = try when.then()
        XCTAssertEqual(result.logs.count, 1)
        let log = result.logs[0]
        log.assertNoValue(forKey: "application_id")
        log.assertNoValue(forKey: "session_id")
        log.assertNoValue(forKey: "view.id")
        log.assertNoValue(forKey: "user_action.id")
    }

    func testGivenRUMFeatureNotEnabled_whenLogIsEmitted_logCarriesNoRUMContextAttributesRegardlessOfBundleFlag() throws {
        // Given / When
        let whenDefaultBundle = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("default bundle flag, RUM disabled")
            }

        let whenBundleDisabled = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.advanceTime(by: timeToSDKInit))
            .and(.initializeSDK())
            .when { app in
                Logs.enable(in: app.core)
                var config = Logger.Configuration()
                config.bundleWithRumEnabled = false
                app.logger = Logger.create(with: config, in: app.core)
                app.logger.info("bundle disabled, RUM disabled")
            }

        // Then
        for when in [whenDefaultBundle, whenBundleDisabled] {
            let result = try when.then()
            XCTAssertEqual(result.sessions.count, 0, "RUM was not enabled — no sessions expected")
            XCTAssertEqual(result.logs.count, 1)
            let log = result.logs[0]
            log.assertNoValue(forKey: "application_id")
            log.assertNoValue(forKey: "session_id")
            log.assertNoValue(forKey: "view.id")
            log.assertNoValue(forKey: "user_action.id")
        }
    }

    func testGivenActiveUserAction_whenLogIsEmitted_logCarriesUserActionIdMatchingActiveAction() throws {
        // Given / When
        let when = AppRun
            .given(.appLaunch(type: .userLaunchInSceneDelegateBasedApp(processLaunchDate: processLaunchDate)))
            .and(.enableRUM(after: timeToSDKInit))
            .and(.startManualView(after: 0.1, viewName: "Cart"))
            .and { app in
                app.rum.startAction(type: .scroll, name: "ScrollProducts")
            }
            .when { app in
                Logs.enable(in: app.core)
                app.logger = Logger.create(in: app.core)
                app.logger.info("during action")
            }
            .and { app in
                app.rum.stopAction(type: .scroll, name: "ScrollProducts")
            }

        // Then
        let result = try when.then()
        let session = try result.sessions.takeSingle()
        let manualView = try XCTUnwrap(session.views.last)
        XCTAssertEqual(manualView.name, "Cart")
        let actionEvent = try XCTUnwrap(manualView.actionEvents.last { $0.action.type == .scroll })

        XCTAssertEqual(result.logs.count, 1)
        let log = result.logs[0]
        let logApplicationId: String = try log.value(forKeyPath: "application_id")
        let logSessionId: String = try log.value(forKeyPath: "session_id")
        let logViewId: String = try log.value(forKeyPath: "view.id")
        let logUserActionId: String = try log.value(forKeyPath: "user_action.id")
        XCTAssertEqual(logApplicationId, session.applicationID)
        XCTAssertEqual(logSessionId, session.sessionID)
        XCTAssertEqual(logViewId, manualView.viewID)
        XCTAssertEqual(logUserActionId, actionEvent.action.id, "Log user_action.id should match the active RUM action UUID")
    }
}
