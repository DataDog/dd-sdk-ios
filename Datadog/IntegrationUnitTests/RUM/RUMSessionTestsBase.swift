/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogCore
@testable import DatadogRUM

/// Base class for RUM session tests.
/// Provides common fixtures and helpers for simulating test scenarios.
class RUMSessionTestsBase: XCTestCase {
    /// Timestamp representing when the app process was spawned.
    let processLaunchDate = Date()
    /// Simulated delay between app launch and SDK initialization (`Datadog.initialize()` + `RUM.enable()`).
    let timeToSDKInit: TimeInterval = 0.7

    /// Simulated delay before the app transitions to the ACTIVE state.
    let timeToAppBecomeActive: TimeInterval = 0.8
    /// Simulated delay before the app transitions to the BACKGROUND state.
    let timeToAppEnterBackground: TimeInterval = 0.9

    /// Time deltas used to advance or compare time in test scenarios.
    let dt1: TimeInterval = 1.1
    let dt2: TimeInterval = 1.2
    let dt3: TimeInterval = 1.3
    let dt4: TimeInterval = 1.4
    let dt5: TimeInterval = 1.5
    let dt6: TimeInterval = 1.6
    let dt7: TimeInterval = 1.7

    /// Allowed accuracy for time-based assertions in tests.
    let accuracy: TimeInterval = 0.01

    /// Name of the standard "ApplicationLaunch" view.
    let applicationLaunchViewName = RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName
    /// Name of the standard "Background" view.
    let backgroundViewName = RUMOffViewEventsHandlingRule.Constants.backgroundViewName
    /// Name of a manually tracked view.
    let manualViewName = "ManualView"
    /// Name of an automatically tracked view.
    let automaticViewName = "AutomaticView"
    /// Mock instance representing the automatic view.
    lazy var automaticView = createMockView(viewControllerClassName: automaticViewName)

    /// Session timeout duration due to user inactivity.
    let sessionTimeoutDuration = RUMSessionScope.Constants.sessionTimeoutDuration

    // MARK: - Starting session with "user_app_launch" precondition

    /// Starts `"user_app_launch"` session with `ApplicationLaunch` view.
    /// ```
    /// [FG:ApplicationLaunch]
    /// ```
    func userSession(rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
        return .given(.appLaunch(type: .userLaunch(processLaunchDate: processLaunchDate)))
            .and(.enableRUM(after: timeToSDKInit, rumSetup: rumSetup))
            .and(.appBecomesActive(after: timeToAppBecomeActive))
    }

    /// Starts `"user_app_launch"` session with `ApplicationLaunch` view succeeded by automatic view started
    /// when app becames ACTIVE.
    /// ```
    /// [FG:ApplicationLaunch] --> [FG:AutomaticView]
    /// ```
    func userSessionWithAutomaticView(rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
        let view = createMockView(viewControllerClassName: automaticViewName)
        return userSession { rumConfig in
            rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
            rumSetup?(&rumConfig)
            precondition(rumConfig.uiKitViewsPredicate is DefaultUIKitRUMViewsPredicate)
        }
        .and(.startAutomaticView(after: 0, viewController: view))
    }

    /// Starts `"user_app_launch"` session with `ApplicationLaunch` view succeeded by manual view started
    /// when app becames ACTIVE.
    /// ```
    /// [FG:ApplicationLaunch] --> [FG:ManualView]
    /// ```
    func userSessionWithManualView(rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
        return userSession(rumSetup: rumSetup)
            .and(.startManualView(after: 0, viewName: manualViewName))
    }

    // MARK: - Starting session with "background_launch" precondition

    /// Starts `"background_launch"` session without starting `Background` view.
    /// ```
    /// [BG:(no view))]
    /// ```
    func backgroundSession(rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
        return .given(.appLaunch(type: .backgroundLaunch(processLaunchDate: processLaunchDate)))
            .and(.enableRUM(after: timeToSDKInit, rumSetup: rumSetup))
    }

    /// Starts `"background_launch"` session that tracks Resource event which creates `Background` view.
    /// ```
    /// [BG:Background]
    /// ```
    func backgroundSessionWithResource(
        resourceStartAfter: TimeInterval,
        resourceDuration: TimeInterval,
        rumSetup: AppRunner.RUMSetup? = nil
    ) -> AppRun {
        return backgroundSession { rumConfig in
            rumConfig.trackBackgroundEvents = true
            rumSetup?(&rumConfig)
            precondition(rumConfig.trackBackgroundEvents)
        }
        .and(.trackResource(after: resourceStartAfter, duration: resourceDuration))
    }

    // MARK: - Starting session with "prewarm" precondition

    /// Starts `"prewarm"` session without starting `Background` view.
    /// ```
    /// [BG:(no view)]
    /// ```
    func prewarmedSession(rumSetup: AppRunner.RUMSetup? = nil) -> AppRun {
        return .given(.appLaunch(type: .osPrewarm(processLaunchDate: processLaunchDate)))
            .and(.enableRUM(after: timeToSDKInit, rumSetup: rumSetup))
    }

    /// Starts `"prewarm"` session that tracks Resource event which creates `Background` view.
    /// ```
    /// [BG:Background]
    /// ```
    func prewarmedSessionWithResource(
        resourceStartAfter: TimeInterval,
        resourceDuration: TimeInterval,
        rumSetup: AppRunner.RUMSetup? = nil
    ) -> AppRun {
        return .given(.appLaunch(type: .osPrewarm(processLaunchDate: processLaunchDate)))
            .and(.enableRUM(after: timeToSDKInit, rumSetup: { rumConfig in
                rumConfig.trackBackgroundEvents = true
                rumSetup?(&rumConfig)
                precondition(rumConfig.trackBackgroundEvents)
            }))
            .and(.trackResource(after: resourceStartAfter, duration: resourceDuration))
    }
}
