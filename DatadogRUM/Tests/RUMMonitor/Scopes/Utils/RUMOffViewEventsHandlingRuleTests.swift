/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import DatadogInternal
import TestUtilities
@testable import DatadogRUM

class RUMOffViewEventsHandlingRuleTests: XCTestCase {
    func testOffViewHandlingRules() {
        struct Case {
            let description: String
            let applicationState: RUMApplicationState?
            let sessionState: RUMSessionState?
            let isAppInForeground: Bool
            let isBETEnabled: Bool
            let canStartBackgroundViewAfterSessionStop: Bool
            let expected: RUMOffViewEventsHandlingRule
        }

        let notSampledSession = RUMSessionState(
            sessionUUID: .nullUUID,
            isInitialSession: true,
            hasTrackedAnyView: false,
            didStartWithReplay: nil
        )

        let initialNoViews = RUMSessionState(
            sessionUUID: UUID(),
            isInitialSession: true,
            hasTrackedAnyView: false,
            didStartWithReplay: nil
        )

        let hasViews = RUMSessionState(
            sessionUUID: UUID(),
            isInitialSession: false,
            hasTrackedAnyView: true,
            didStartWithReplay: nil
        )

        let cases: [Case] = [
            .init(
                description: "session not sampled (nullUUID)",
                applicationState: nil,
                sessionState: notSampledSession,
                isAppInForeground: true,
                isBETEnabled: true,
                canStartBackgroundViewAfterSessionStop: true,
                expected: .doNotHandle
            ),
            .init(
                description: "initial session without views in foreground",
                applicationState: nil,
                sessionState: initialNoViews,
                isAppInForeground: true,
                isBETEnabled: false,
                canStartBackgroundViewAfterSessionStop: true,
                expected: .handleInApplicationLaunchView
            ),
            .init(
                description: "initial session without views in background when BET disabled",
                applicationState: nil,
                sessionState: initialNoViews,
                isAppInForeground: false,
                isBETEnabled: false,
                canStartBackgroundViewAfterSessionStop: true,
                expected: .doNotHandle
            ),
            .init(
                description: "initial session without views in background when BET enabled",
                applicationState: nil,
                sessionState: initialNoViews,
                isAppInForeground: false,
                isBETEnabled: true,
                canStartBackgroundViewAfterSessionStop: true,
                expected: .handleInBackgroundView
            ),
            .init(
                description: "initial session resumes in background after previous session stopped",
                applicationState: RUMApplicationState(wasPreviousSessionStopped: true),
                sessionState: initialNoViews,
                isAppInForeground: false,
                isBETEnabled: true,
                canStartBackgroundViewAfterSessionStop: false,
                expected: .doNotHandle
            ),
            .init(
                description: "existing views present in foreground",
                applicationState: RUMApplicationState(numberOfNonApplicationLaunchViewsCreated: 1),
                sessionState: hasViews,
                isAppInForeground: true,
                isBETEnabled: true,
                canStartBackgroundViewAfterSessionStop: true,
                expected: .doNotHandle
            ),
            .init(
                description: "existing views present in background when BET enabled",
                applicationState: RUMApplicationState(numberOfNonApplicationLaunchViewsCreated: 1),
                sessionState: hasViews,
                isAppInForeground: false,
                isBETEnabled: true,
                canStartBackgroundViewAfterSessionStop: true,
                expected: .handleInBackgroundView
            ),
            .init(
                description: "existing views in background after session stopped cannot start new background view",
                applicationState: RUMApplicationState(numberOfNonApplicationLaunchViewsCreated: 1, wasPreviousSessionStopped: true),
                sessionState: hasViews,
                isAppInForeground: false,
                isBETEnabled: true,
                canStartBackgroundViewAfterSessionStop: false,
                expected: .doNotHandle
            ),
            .init(
                description: "no session state in foreground after any session stopped",
                applicationState: RUMApplicationState(wasAnySessionStopped: true),
                sessionState: nil,
                isAppInForeground: true,
                isBETEnabled: true,
                canStartBackgroundViewAfterSessionStop: true,
                expected: .doNotHandle
            ),
            .init(
                description: "no session state in foreground on fresh launch",
                applicationState: RUMApplicationState(wasAnySessionStopped: false),
                sessionState: nil,
                isAppInForeground: true,
                isBETEnabled: false,
                canStartBackgroundViewAfterSessionStop: true,
                expected: .handleInApplicationLaunchView
            ),
            .init(
                description: "no session state in background when BET enabled",
                applicationState: RUMApplicationState(wasPreviousSessionStopped: false),
                sessionState: nil,
                isAppInForeground: false,
                isBETEnabled: true,
                canStartBackgroundViewAfterSessionStop: true,
                expected: .handleInBackgroundView
            ),
            .init(
                description: "no session state in background after previous session stopped",
                applicationState: RUMApplicationState(wasPreviousSessionStopped: true),
                sessionState: nil,
                isAppInForeground: false,
                isBETEnabled: true,
                canStartBackgroundViewAfterSessionStop: false,
                expected: .doNotHandle
            ),
            .init(
                description: "no session state in background when BET disabled",
                applicationState: RUMApplicationState(wasPreviousSessionStopped: false),
                sessionState: nil,
                isAppInForeground: false,
                isBETEnabled: false,
                canStartBackgroundViewAfterSessionStop: true,
                expected: .doNotHandle
            )
        ]

        for testCase in cases {
            let result = RUMOffViewEventsHandlingRule(
                applicationState: testCase.applicationState,
                sessionState: testCase.sessionState,
                isAppInForeground: testCase.isAppInForeground,
                isBETEnabled: testCase.isBETEnabled,
                command: RUMCommandMock(canStartBackgroundViewAfterSessionStop: testCase.canStartBackgroundViewAfterSessionStop)
            )
            XCTAssertEqual(result, testCase.expected, "Failed: \(testCase.description) -> got \(result)")
        }
    }
}
