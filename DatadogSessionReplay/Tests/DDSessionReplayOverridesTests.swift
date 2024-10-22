/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import XCTest
import TestUtilities
import DatadogInternal
@_spi(objc)
@testable import DatadogSessionReplay

class DDSessionReplayOverrideTests: XCTestCase {
    // MARK: Privacy Overrides Interoperability
    func testTextAndInputPrivacyLevelsOverrideInterop() {
        XCTAssertEqual(objc_TextAndInputPrivacyLevelOverride.maskAll._swift, .maskAll)
        XCTAssertEqual(objc_TextAndInputPrivacyLevelOverride.maskAllInputs._swift, .maskAllInputs)
        XCTAssertEqual(objc_TextAndInputPrivacyLevelOverride.maskSensitiveInputs._swift, .maskSensitiveInputs)
        XCTAssertNil(objc_TextAndInputPrivacyLevelOverride.none._swift)

        XCTAssertEqual(objc_TextAndInputPrivacyLevelOverride(.maskAll), .maskAll)
        XCTAssertEqual(objc_TextAndInputPrivacyLevelOverride(.maskAllInputs), .maskAllInputs)
        XCTAssertEqual(objc_TextAndInputPrivacyLevelOverride(.maskSensitiveInputs), .maskSensitiveInputs)
        XCTAssertEqual(objc_TextAndInputPrivacyLevelOverride(nil), .none)
    }

    func testImagePrivacyLevelsOverrideInterop() {
        XCTAssertEqual(objc_ImagePrivacyLevelOverride.maskAll._swift, .maskAll)
        XCTAssertEqual(objc_ImagePrivacyLevelOverride.maskNonBundledOnly._swift, .maskNonBundledOnly)
        XCTAssertEqual(objc_ImagePrivacyLevelOverride.maskNone._swift, .maskNone)
        XCTAssertNil(objc_ImagePrivacyLevelOverride.none._swift)

        XCTAssertEqual(objc_ImagePrivacyLevelOverride(.maskAll), .maskAll)
        XCTAssertEqual(objc_ImagePrivacyLevelOverride(.maskNonBundledOnly), .maskNonBundledOnly)
        XCTAssertEqual(objc_ImagePrivacyLevelOverride(.maskNone), .maskNone)
        XCTAssertEqual(objc_ImagePrivacyLevelOverride(nil), .none)
    }

    func testTouchPrivacyLevelsOverrideInterop() {
        XCTAssertEqual(objc_TouchPrivacyLevelOverride.show._swift, .show)
        XCTAssertEqual(objc_TouchPrivacyLevelOverride.hide._swift, .hide)
        XCTAssertNil(objc_TouchPrivacyLevelOverride.none._swift)

        XCTAssertEqual(objc_TouchPrivacyLevelOverride(.show), .show)
        XCTAssertEqual(objc_TouchPrivacyLevelOverride(.hide), .hide)
        XCTAssertEqual(objc_TouchPrivacyLevelOverride(nil), .none)
    }

    func testHidePrivacyLevelsOverrideInterop() {
        // Testing Swift -> Objective-C interaction
        let view = UIView()
        let objcOverrides = view.ddSessionReplayPrivacyOverrides

        // Set via Swift
        view.dd.sessionReplayPrivacyOverrides.hide = true
        XCTAssertEqual(objcOverrides.hide, NSNumber(value: true))

        view.dd.sessionReplayPrivacyOverrides.hide = false
        XCTAssertEqual(objcOverrides.hide, NSNumber(value: false))

        view.dd.sessionReplayPrivacyOverrides.hide = nil
        XCTAssertNil(objcOverrides.hide)

        // Set via Objective-C
        objcOverrides.hide = NSNumber(value: true)
        XCTAssertEqual(view.dd.sessionReplayPrivacyOverrides.hide, true)

        objcOverrides.hide = NSNumber(value: false)
        XCTAssertEqual(view.dd.sessionReplayPrivacyOverrides.hide, false)

        objcOverrides.hide = nil
        XCTAssertNil(view.dd.sessionReplayPrivacyOverrides.hide)
    }

    // MARK: Setting Privacy Overrides
    func testSettingAndClearingObjectOverridesInObjc() {
        // Given
        let textAndInputPrivacy: objc_TextAndInputPrivacyLevelOverride = .mockRandom()
        let imagePrivacy: objc_ImagePrivacyLevelOverride = .mockRandom()
        let touchPrivacy: objc_TouchPrivacyLevelOverride = .mockRandom()
        let hidePrivacy = NSNumber.mockRandomHidePrivacy()

        // When
        let overrides = objc_SessionReplayPrivacyOverrides(view: UIView())
        overrides.textAndInputPrivacy = textAndInputPrivacy
        overrides.imagePrivacy = imagePrivacy
        overrides.touchPrivacy = touchPrivacy
        overrides.hide = hidePrivacy

        // Then
        XCTAssertEqual(overrides.textAndInputPrivacy, textAndInputPrivacy)
        XCTAssertEqual(overrides.imagePrivacy, imagePrivacy)
        XCTAssertEqual(overrides.touchPrivacy, touchPrivacy)
        XCTAssertEqual(overrides.hide, hidePrivacy)

        // When
        overrides.textAndInputPrivacy = .none
        overrides.imagePrivacy = .none
        overrides.touchPrivacy = .none
        overrides.hide = false

        // Then
        XCTAssertEqual(overrides.textAndInputPrivacy, .none)
        XCTAssertEqual(overrides.imagePrivacy, .none)
        XCTAssertEqual(overrides.touchPrivacy, .none)
        XCTAssertEqual(overrides.hide, false)
    }

    func testSettingAndClearingViewOverridesInObjc() {
        // Given
        let view = UIView()
        let textAndInputPrivacy: objc_TextAndInputPrivacyLevelOverride = .mockRandom()
        let imagePrivacy: objc_ImagePrivacyLevelOverride = .mockRandom()
        let touchPrivacy: objc_TouchPrivacyLevelOverride = .mockRandom()
        let hidePrivacy = NSNumber.mockRandomHidePrivacy()

        // When
        view.ddSessionReplayPrivacyOverrides.textAndInputPrivacy = textAndInputPrivacy
        view.ddSessionReplayPrivacyOverrides.imagePrivacy = imagePrivacy
        view.ddSessionReplayPrivacyOverrides.touchPrivacy = touchPrivacy
        view.ddSessionReplayPrivacyOverrides.hide = hidePrivacy

        // Then
        XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.textAndInputPrivacy, textAndInputPrivacy)
        XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.imagePrivacy, imagePrivacy)
        XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.touchPrivacy, touchPrivacy)
        XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.hide, hidePrivacy)

        // When
        view.ddSessionReplayPrivacyOverrides.textAndInputPrivacy = .none
        view.ddSessionReplayPrivacyOverrides.imagePrivacy = .none
        view.ddSessionReplayPrivacyOverrides.touchPrivacy = .none
        view.ddSessionReplayPrivacyOverrides.hide = nil

        // Then
        XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.textAndInputPrivacy, .none)
        XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.imagePrivacy, .none)
        XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.touchPrivacy, .none)
        XCTAssertNil(view.ddSessionReplayPrivacyOverrides.hide)
    }

    func testSwiftChangesReflectInObjC() {
        // Given
        let view = UIView()
        let textAndInputPrivacy: objc_TextAndInputPrivacyLevelOverride = .mockRandom()
        let imagePrivacy: objc_ImagePrivacyLevelOverride = .mockRandom()
        let touchPrivacy: objc_TouchPrivacyLevelOverride = .mockRandom()
        let hidePrivacy = NSNumber.mockRandomHidePrivacy()

        // When (set in Swift)
        view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = textAndInputPrivacy._swift
        view.dd.sessionReplayPrivacyOverrides.imagePrivacy = imagePrivacy._swift
        view.dd.sessionReplayPrivacyOverrides.touchPrivacy = touchPrivacy._swift
        view.dd.sessionReplayPrivacyOverrides.hide = hidePrivacy?.boolValue

        // Then (check in ObjC)
        XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.textAndInputPrivacy, textAndInputPrivacy)
        XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.imagePrivacy, imagePrivacy)
        XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.touchPrivacy, touchPrivacy)
        XCTAssertEqual(view.ddSessionReplayPrivacyOverrides.hide, hidePrivacy)
    }

    func testObjCChangesReflectInSwift() {
        // Given
        let view = UIView()
        let textAndInputPrivacy: objc_TextAndInputPrivacyLevelOverride = .mockRandom()
        let imagePrivacy: objc_ImagePrivacyLevelOverride = .mockRandom()
        let touchPrivacy: objc_TouchPrivacyLevelOverride = .mockRandom()
        let hidePrivacy = NSNumber.mockRandomHidePrivacy()

        // When (set in ObjC)
        view.ddSessionReplayPrivacyOverrides.textAndInputPrivacy = textAndInputPrivacy
        view.ddSessionReplayPrivacyOverrides.imagePrivacy = imagePrivacy
        view.ddSessionReplayPrivacyOverrides.touchPrivacy = touchPrivacy
        view.ddSessionReplayPrivacyOverrides.hide = hidePrivacy

        // Then (check in Swift)
        XCTAssertEqual(view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy, textAndInputPrivacy._swift)
        XCTAssertEqual(view.dd.sessionReplayPrivacyOverrides.imagePrivacy, imagePrivacy._swift)
        XCTAssertEqual(view.dd.sessionReplayPrivacyOverrides.touchPrivacy, touchPrivacy._swift)
        XCTAssertEqual(view.dd.sessionReplayPrivacyOverrides.hide, hidePrivacy?.boolValue)
    }

    func testReleasingOverridesWhenViewIsDeallocated() {
        weak var view: UIView?

        autoreleasepool {
            let tempView = UIView()
            view = tempView
            tempView.ddSessionReplayPrivacyOverrides.textAndInputPrivacy = .mockRandom()
            tempView.ddSessionReplayPrivacyOverrides.imagePrivacy = .mockRandom()
            tempView.ddSessionReplayPrivacyOverrides.touchPrivacy = .mockRandom()
            tempView.ddSessionReplayPrivacyOverrides.hide = NSNumber.mockRandomHidePrivacy()
        }

        XCTAssertNil(view?.ddSessionReplayPrivacyOverrides.textAndInputPrivacy)
        XCTAssertNil(view?.ddSessionReplayPrivacyOverrides.imagePrivacy)
        XCTAssertNil(view?.ddSessionReplayPrivacyOverrides.touchPrivacy)
        XCTAssertNil(view?.ddSessionReplayPrivacyOverrides.hide)
    }
}
#endif
