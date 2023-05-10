/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

class RUMOffViewEventsHandlingRuleTests: XCTestCase {
    // MARK: - When There Is No RUM Session

    func testWhenThereIsNoRUMSessionAndAppIsInForeground_itShouldHandleEventsInApplicationLaunchView() {
        let rule = RUMOffViewEventsHandlingRule(
            sessionState: nil,
            isAppInForeground: true,
            isBETEnabled: .mockRandom()
        )
        XCTAssertEqual(rule, .handleInApplicationLaunchView, "It must start ApplicationLaunch view, because app is in foreground")
    }

    func testWhenThereIsNoRUMSessionAndAppIsInBackground_itShouldHandleEventsInBackgroundView_onlyWhenBETIsEnabled() {
        let rule1 = RUMOffViewEventsHandlingRule(
            sessionState: nil,
            isAppInForeground: false,
            isBETEnabled: true
        )
        XCTAssertEqual(rule1, .handleInBackgroundView, "It must start Background view")

        let rule2 = RUMOffViewEventsHandlingRule(
            sessionState: nil,
            isAppInForeground: false,
            isBETEnabled: false
        )
        XCTAssertEqual(rule2, .doNotHandle, "It must drop the event, because BET is disabled")
    }

    // MARK: - When There Is RUM Session

    func testWhenThereIsRUMSessionAndAppIsInForeground_itShouldHandleEventsInApplicationLaunchView_onlyWhenInitialSessionWithNoViewsHistory() {
        let rule1 = RUMOffViewEventsHandlingRule(
            sessionState: .init(
                sessionUUID: .mockRandom(),
                isInitialSession: true,
                hasTrackedAnyView: false,
                didStartWithReplay: .mockAny()
            ),
            isAppInForeground: true,
            isBETEnabled: .mockRandom()
        )
        XCTAssertEqual(rule1, .handleInApplicationLaunchView, "It must start ApplicationLaunch view")

        let rule2 = RUMOffViewEventsHandlingRule(
            sessionState: .init(
                sessionUUID: .mockRandom(),
                isInitialSession: .mockRandom(),
                hasTrackedAnyView: true,
                didStartWithReplay: .mockAny()
            ),
            isAppInForeground: true,
            isBETEnabled: .mockRandom()
        )
        XCTAssertEqual(rule2, .doNotHandle, "It must drop the event, because this session already tracked some views")

        let rule3 = RUMOffViewEventsHandlingRule(
            sessionState: .init(
                sessionUUID: .mockRandom(),
                isInitialSession: false,
                hasTrackedAnyView: .mockRandom(),
                didStartWithReplay: .mockAny()
            ),
            isAppInForeground: true,
            isBETEnabled: .mockRandom()
        )
        XCTAssertEqual(rule3, .doNotHandle, "It must drop the event, because this is not initial session")
    }

    func testWhenThereIsRUMSessionAndAppIsInBackground_itShouldHandleEventsInBackgroundView_onlyWhenBETIsEnabled() {
        let rule1 = RUMOffViewEventsHandlingRule(
            sessionState: .init(
                sessionUUID: .mockRandom(),
                isInitialSession: .mockRandom(),
                hasTrackedAnyView: .mockRandom(),
                didStartWithReplay: .mockAny()
            ),
            isAppInForeground: false,
            isBETEnabled: true
        )
        XCTAssertEqual(rule1, .handleInBackgroundView, "It must start Background view")

        let rule2 = RUMOffViewEventsHandlingRule(
            sessionState: .init(
                sessionUUID: .mockRandom(),
                isInitialSession: .mockRandom(),
                hasTrackedAnyView: .mockRandom(),
                didStartWithReplay: .mockAny()
            ),
            isAppInForeground: false,
            isBETEnabled: false
        )
        XCTAssertEqual(rule2, .doNotHandle, "It must drop the event, because BET is disabled")
    }

    // MARK: - When There Is RUM Session But It Is Rejected By Sampler

    func testWhenThereIsRUMSessionButItIsRejectedBySampler_itShouldDropAllEvents() {
        let rule = RUMOffViewEventsHandlingRule(
            sessionState: .init(
                sessionUUID: .nullUUID, // session is not sampled
                isInitialSession: .mockRandom(),
                hasTrackedAnyView: .mockRandom(),
                didStartWithReplay: .mockAny()
            ),
            isAppInForeground: .mockRandom(),
            isBETEnabled: .mockRandom()
        )
        XCTAssertEqual(rule, .doNotHandle, "It must drop the event, because session is not sampled")
    }
}
