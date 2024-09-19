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
        XCTAssertEqual(DDHiddenPrivacyLevelOverride.hide._swift, .hide)
        XCTAssertNil(DDHiddenPrivacyLevelOverride.none._swift)

        XCTAssertEqual(DDHiddenPrivacyLevelOverride(.hide), .hide)
        XCTAssertEqual(DDHiddenPrivacyLevelOverride(nil), .none)
    }

    func testSettingAndRemovingPrivacyOverridesObjc() {
        // Given
        let override = DDSessionReplayOverride()
        let textAndInputPrivacy: DDTextAndInputPrivacyLevelOverride = [.maskAll, .maskAllInputs, .maskSensitiveInputs].randomElement()!
        let imagePrivacy: DDImagePrivacyLevelOverride = [.maskAll, .maskNonBundledOnly, .maskNone].randomElement()!
        let touchPrivacy: DDTouchPrivacyLevelOverride = [.show, .hide].randomElement()!
        let hiddenPrivacy: DDHiddenPrivacyLevelOverride = [.hide, .none].randomElement()!

        // When
        override.textAndInputPrivacy = textAndInputPrivacy
        override.imagePrivacy = imagePrivacy
        override.touchPrivacy = touchPrivacy
        override.hiddenPrivacy = hiddenPrivacy

        // Then
        XCTAssertEqual(override.textAndInputPrivacy, textAndInputPrivacy)
        XCTAssertEqual(override.imagePrivacy, imagePrivacy)
        XCTAssertEqual(override.touchPrivacy, touchPrivacy)
        XCTAssertEqual(override.hiddenPrivacy, hiddenPrivacy)

        // When
        override.textAndInputPrivacy = .none
        override.imagePrivacy = .none
        override.touchPrivacy = .none
        override.hiddenPrivacy = .none

        // Then
        XCTAssertEqual(override.textAndInputPrivacy, .none)
        XCTAssertEqual(override.imagePrivacy, .none)
        XCTAssertEqual(override.touchPrivacy, .none)
        XCTAssertEqual(override.hiddenPrivacy, .none)
    }
}
#endif
