/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import UIKit
@testable import DatadogSessionReplay

class SessionReplayOverrideTests: XCTestCase {
    func testWhenNoOverrideIsSet_itDefaultsToNil() {
        // Given
        let view = UIView()

        // Then
        XCTAssertNil(view.dd.sessionReplayOverride.textAndInputPrivacy)
        XCTAssertNil(view.dd.sessionReplayOverride.imagePrivacy)
        XCTAssertNil(view.dd.sessionReplayOverride.touchPrivacy)
        XCTAssertNil(view.dd.sessionReplayOverride.hidden)
    }

    func testWithOverrides() {
        // Given
        let view = UIView()

        // When
        view.dd.sessionReplayOverride.textAndInputPrivacy = .maskAllInputs
        view.dd.sessionReplayOverride.imagePrivacy = .maskAll
        view.dd.sessionReplayOverride.touchPrivacy = .hide
        view.dd.sessionReplayOverride.hidden = true

        // Then
        XCTAssertEqual(view.dd.sessionReplayOverride.textAndInputPrivacy, .maskAllInputs)
        XCTAssertEqual(view.dd.sessionReplayOverride.imagePrivacy, .maskAll)
        XCTAssertEqual(view.dd.sessionReplayOverride.touchPrivacy, .hide)
        XCTAssertEqual(view.dd.sessionReplayOverride.hidden, true)
    }

    func testRemovingOverrides() {
        // Given
        let view = UIView()
        view.dd.sessionReplayOverride.textAndInputPrivacy = .maskAllInputs
        view.dd.sessionReplayOverride.imagePrivacy = .maskAll
        view.dd.sessionReplayOverride.touchPrivacy = .hide
        view.dd.sessionReplayOverride.hidden = true

        // When
        view.dd.sessionReplayOverride.textAndInputPrivacy = nil
        view.dd.sessionReplayOverride.imagePrivacy = nil
        view.dd.sessionReplayOverride.touchPrivacy = nil
        view.dd.sessionReplayOverride.hidden = nil

        // Then
        XCTAssertNil(view.dd.sessionReplayOverride.textAndInputPrivacy)
        XCTAssertNil(view.dd.sessionReplayOverride.imagePrivacy)
        XCTAssertNil(view.dd.sessionReplayOverride.touchPrivacy)
        XCTAssertNil(view.dd.sessionReplayOverride.hidden)
    }
}
#endif
