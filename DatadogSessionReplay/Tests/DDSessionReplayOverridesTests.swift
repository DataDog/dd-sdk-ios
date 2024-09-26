/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
import TestUtilities
import DatadogInternal

@testable import DatadogSessionReplay

class DDSessionReplayOverrideTests: XCTestCase {
    // MARK: Overrides Interoperability
    func testTextAndInputPrivacyLevelsOverrideInterop() {
        XCTAssertEqual(DDTextAndInputPrivacyLevelOverride.maskAll._swift, .maskAll)
        XCTAssertEqual(DDTextAndInputPrivacyLevelOverride.maskAllInputs._swift, .maskAllInputs)
        XCTAssertEqual(DDTextAndInputPrivacyLevelOverride.maskSensitiveInputs._swift, .maskSensitiveInputs)
        XCTAssertNil(DDTextAndInputPrivacyLevelOverride.none._swift)

        XCTAssertEqual(DDTextAndInputPrivacyLevelOverride(.maskAll), .maskAll)
        XCTAssertEqual(DDTextAndInputPrivacyLevelOverride(.maskAllInputs), .maskAllInputs)
        XCTAssertEqual(DDTextAndInputPrivacyLevelOverride(.maskSensitiveInputs), .maskSensitiveInputs)
        XCTAssertEqual(DDTextAndInputPrivacyLevelOverride(nil), .none)
    }

    func testImagePrivacyLevelsOverrideInterop() {
        XCTAssertEqual(DDImagePrivacyLevelOverride.maskAll._swift, .maskAll)
        XCTAssertEqual(DDImagePrivacyLevelOverride.maskNonBundledOnly._swift, .maskNonBundledOnly)
        XCTAssertEqual(DDImagePrivacyLevelOverride.maskNone._swift, .maskNone)
        XCTAssertNil(DDImagePrivacyLevelOverride.none._swift)

        XCTAssertEqual(DDImagePrivacyLevelOverride(.maskAll), .maskAll)
        XCTAssertEqual(DDImagePrivacyLevelOverride(.maskNonBundledOnly), .maskNonBundledOnly)
        XCTAssertEqual(DDImagePrivacyLevelOverride(.maskNone), .maskNone)
        XCTAssertEqual(DDImagePrivacyLevelOverride(nil), .none)
    }

    func testTouchPrivacyLevelsOverrideInterop() {
        XCTAssertEqual(DDTouchPrivacyLevelOverride.show._swift, .show)
        XCTAssertEqual(DDTouchPrivacyLevelOverride.hide._swift, .hide)
        XCTAssertNil(DDTouchPrivacyLevelOverride.none._swift)

        XCTAssertEqual(DDTouchPrivacyLevelOverride(.show), .show)
        XCTAssertEqual(DDTouchPrivacyLevelOverride(.hide), .hide)
        XCTAssertEqual(DDTouchPrivacyLevelOverride(nil), .none)
    }

    func testHiddenPrivacyLevelsOverrideInterop() {
        let override = DDSessionReplayOverride()

        // When setting hiddenPrivacy via Swift
        override._swift.hide = true
        XCTAssertEqual(override.hide, NSNumber(value: true))

        override._swift.hide = false
        XCTAssertEqual(override.hide, NSNumber(value: false))

        override._swift.hide = nil
        XCTAssertNil(override.hide)

        // When setting hiddenPrivacy via Objective-C
        override.hide = NSNumber(value: true)
        XCTAssertEqual(override._swift.hide, true)

        override.hide = NSNumber(value: false)
        XCTAssertEqual(override._swift.hide, false)

        override.hide = nil
        XCTAssertNil(override._swift.hide)
    }

    // MARK: Setting Overrides
    func testSettingAndRemovingPrivacyOverridesObjc() {
        // Given
        let override = DDSessionReplayOverride()
        let textAndInputPrivacy: DDTextAndInputPrivacyLevelOverride = [.maskAll, .maskAllInputs, .maskSensitiveInputs].randomElement()!
        let imagePrivacy: DDImagePrivacyLevelOverride = [.maskAll, .maskNonBundledOnly, .maskNone].randomElement()!
        let touchPrivacy: DDTouchPrivacyLevelOverride = [.show, .hide].randomElement()!
        let hide: NSNumber? = [true, false].randomElement().map { NSNumber(value: $0) } ?? nil

        // When
        override.textAndInputPrivacy = textAndInputPrivacy
        override.imagePrivacy = imagePrivacy
        override.touchPrivacy = touchPrivacy
        override.hide = hide

        // Then
        XCTAssertEqual(override.textAndInputPrivacy, textAndInputPrivacy)
        XCTAssertEqual(override.imagePrivacy, imagePrivacy)
        XCTAssertEqual(override.touchPrivacy, touchPrivacy)
        XCTAssertEqual(override.hide, hide)

        // When
        override.textAndInputPrivacy = .none
        override.imagePrivacy = .none
        override.touchPrivacy = .none
        override.hide = false

        // Then
        XCTAssertEqual(override.textAndInputPrivacy, .none)
        XCTAssertEqual(override.imagePrivacy, .none)
        XCTAssertEqual(override.touchPrivacy, .none)
        XCTAssertEqual(override.hide, false)
    }

    func testSettingAndGettingOverridesFromObjC() {
            // Given
            let view = UIView()
            let override = DDSessionReplayOverride()

            // When
            view.ddSessionReplayOverride = override
            override.textAndInputPrivacy = .maskAll
            override.imagePrivacy = .maskAll
            override.touchPrivacy = .hide
            override.hide = NSNumber(value: true)

            // Then
            XCTAssertEqual(view.ddSessionReplayOverride.textAndInputPrivacy, .maskAll)
            XCTAssertEqual(view.ddSessionReplayOverride.imagePrivacy, .maskAll)
            XCTAssertEqual(view.ddSessionReplayOverride.touchPrivacy, .hide)
            XCTAssertEqual(view.ddSessionReplayOverride.hide?.boolValue, true)
        }

        func testClearingOverridesFromObjC() {
            // Given
            let view = UIView()
            let override = DDSessionReplayOverride()

            // Set initial values
            view.ddSessionReplayOverride = override
            override.textAndInputPrivacy = .maskAll
            override.imagePrivacy = .maskAll
            override.touchPrivacy = .hide
            override.hide = NSNumber(value: true)

            // When
            view.ddSessionReplayOverride.textAndInputPrivacy = .none
            view.ddSessionReplayOverride.imagePrivacy = .none
            view.ddSessionReplayOverride.touchPrivacy = .none
            view.ddSessionReplayOverride.hide = nil

            // Then
            XCTAssertEqual(view.ddSessionReplayOverride.textAndInputPrivacy, .none)
            XCTAssertEqual(view.ddSessionReplayOverride.imagePrivacy, .none)
            XCTAssertEqual(view.ddSessionReplayOverride.touchPrivacy, .none)
            XCTAssertNil(view.ddSessionReplayOverride.hide)
        }
}
#endif
