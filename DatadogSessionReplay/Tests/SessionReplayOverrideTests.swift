/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import XCTest
import UIKit
@_spi(Internal)
@testable import DatadogSessionReplay

class SessionReplayOverridesTests: XCTestCase {
    // MARK: Setting overrides
    func testWhenNoOverrideIsSet_itDefaultsToNil() {
        // Given
        let view = UIView()

        // Then
        XCTAssertNil(view.dd.sessionReplayOverrides.textAndInputPrivacy)
        XCTAssertNil(view.dd.sessionReplayOverrides.imagePrivacy)
        XCTAssertNil(view.dd.sessionReplayOverrides.touchPrivacy)
        XCTAssertNil(view.dd.sessionReplayOverrides.hide)
    }

    func testWithOverrides() {
        // Given
        let view = UIView()

        // When
        view.dd.sessionReplayOverrides.textAndInputPrivacy = .maskAllInputs
        view.dd.sessionReplayOverrides.imagePrivacy = .maskAll
        view.dd.sessionReplayOverrides.touchPrivacy = .hide
        view.dd.sessionReplayOverrides.hide = true

        // Then
        XCTAssertEqual(view.dd.sessionReplayOverrides.textAndInputPrivacy, .maskAllInputs)
        XCTAssertEqual(view.dd.sessionReplayOverrides.imagePrivacy, .maskAll)
        XCTAssertEqual(view.dd.sessionReplayOverrides.touchPrivacy, .hide)
        XCTAssertEqual(view.dd.sessionReplayOverrides.hide, true)
    }

    func testRemovingOverrides() {
        // Given
        let view = UIView()
        view.dd.sessionReplayOverrides.textAndInputPrivacy = .maskAllInputs
        view.dd.sessionReplayOverrides.imagePrivacy = .maskAll
        view.dd.sessionReplayOverrides.touchPrivacy = .hide
        view.dd.sessionReplayOverrides.hide = true

        // When
        view.dd.sessionReplayOverrides.textAndInputPrivacy = nil
        view.dd.sessionReplayOverrides.imagePrivacy = nil
        view.dd.sessionReplayOverrides.touchPrivacy = nil
        view.dd.sessionReplayOverrides.hide = nil

        // Then
        XCTAssertNil(view.dd.sessionReplayOverrides.textAndInputPrivacy)
        XCTAssertNil(view.dd.sessionReplayOverrides.imagePrivacy)
        XCTAssertNil(view.dd.sessionReplayOverrides.touchPrivacy)
        XCTAssertNil(view.dd.sessionReplayOverrides.hide)
    }

    // MARK: Privacy overrides taking precedence over global settings
    func testTextOverrideTakesPrecedenceOverGlobalTextPrivacy() {
        // Given
        let textAndInputOverride: TextAndInputPrivacyLevel = .mockRandom()
        let viewAttributes: ViewAttributes = .mockWith(overrides: .mockWith(textAndInputPrivacy: textAndInputOverride))
        let globalTextAndInputPrivacy: TextAndInputPrivacyLevel = .mockRandom()
        let context = ViewTreeRecordingContext.mockWith(recorder: .mockWith(textAndInputPrivacy: globalTextAndInputPrivacy))

        // When
        let resolvedTextPrivacy = viewAttributes.resolveTextAndInputPrivacyLevel(in: context)

        // Then
        XCTAssertEqual(resolvedTextPrivacy, textAndInputOverride)
    }

    func testTextGlobalPrivacyIsUsedWhenNoTextOverrideIsSet() {
        // Given
        let viewAttributes: ViewAttributes = .mockAny()
        let globalTextAndInputPrivacy: TextAndInputPrivacyLevel = .mockRandom()
        let context = ViewTreeRecordingContext.mockWith(recorder: .mockWith(textAndInputPrivacy: globalTextAndInputPrivacy))

        // When
        let resolvedPrivacy = viewAttributes.resolveTextAndInputPrivacyLevel(in: context)

        // Then
        XCTAssertEqual(resolvedPrivacy, globalTextAndInputPrivacy)
    }

    func testImageOverrideTakesPrecedenceOverGlobalImagePrivacy() {
        // Given
        let imageOverride: ImagePrivacyLevel = .mockRandom()
        let viewAttributes: ViewAttributes = .mockWith(overrides: .mockWith(imagePrivacy: imageOverride))
        let globalImagePrivacy: ImagePrivacyLevel = .mockRandom()
        let context = ViewTreeRecordingContext.mockWith(recorder: .mockWith(imagePrivacy: globalImagePrivacy))

        // When
        let resolvedImagePrivacy = viewAttributes.resolveImagePrivacyLevel(in: context)

        // Then
        XCTAssertEqual(resolvedImagePrivacy, imageOverride)
    }

    func testImageGlobalPrivacyIsUsedWhenNoImageOverrideIsSet() {
        // Given
        let viewAttributes: ViewAttributes = .mockAny()
        let globalImagePrivacy: ImagePrivacyLevel = .mockRandom()
        let context = ViewTreeRecordingContext.mockWith(recorder: .mockWith(imagePrivacy: globalImagePrivacy))

        // When
        let resolvedImagePrivacy = viewAttributes.resolveImagePrivacyLevel(in: context)

        // Then
        XCTAssertEqual(resolvedImagePrivacy, globalImagePrivacy)
    }

    func testMergeParentAndChildOverrides() {
        // Given
        let overrides: Overrides = .mockRandom()

        let childOverrides: Overrides = .mockAny()
        childOverrides.textAndInputPrivacy = overrides.textAndInputPrivacy
        // We set the `hide` override on the child because in the merge process,
        // the child's override takes precedence. If the parent's `hide` is `false`,
        // the final merged value will end up as `nil`, which makes the test fail.
        childOverrides.hide = overrides.hide

        let parentOverrides: Overrides = .mockAny()
        parentOverrides.imagePrivacy = overrides.imagePrivacy
        parentOverrides.touchPrivacy = overrides.touchPrivacy

        // When
        let merged = SessionReplayOverrides.merge(childOverrides, with: parentOverrides)

        // Then
        XCTAssertEqual(merged.textAndInputPrivacy, overrides.textAndInputPrivacy)
        XCTAssertEqual(merged.imagePrivacy, overrides.imagePrivacy)
        XCTAssertEqual(merged.touchPrivacy, overrides.touchPrivacy)
        XCTAssertEqual(merged.touchPrivacy, overrides.touchPrivacy)
    }

    func testMergeWithNilParentOverrides() {
        // Given
        let childOverrides: Overrides = .mockRandom()
        let parentOverrides: Overrides = .mockAny()

        // When
        let merged = SessionReplayOverrides.merge(childOverrides, with: parentOverrides)

        // Then
        XCTAssertEqual(merged.textAndInputPrivacy, childOverrides.textAndInputPrivacy)
        XCTAssertEqual(merged.imagePrivacy, childOverrides.imagePrivacy)
        XCTAssertEqual(merged.touchPrivacy, childOverrides.touchPrivacy)
        XCTAssertEqual(merged.hide, childOverrides.hide)
    }

    func testMergeWithNilChildOverrides() {
        // Given
        let childOverrides: Overrides = .mockAny()
        let parentOverrides: Overrides = .mockRandom()

        // When
        let merged = SessionReplayOverrides.merge(childOverrides, with: parentOverrides)

        // Then
        XCTAssertEqual(merged.textAndInputPrivacy, parentOverrides.textAndInputPrivacy)
        XCTAssertEqual(merged.imagePrivacy, parentOverrides.imagePrivacy)
        XCTAssertEqual(merged.touchPrivacy, parentOverrides.touchPrivacy)
        XCTAssertEqual(merged.hide, parentOverrides.hide)
    }

    func testMergeWhenChildHideOverrideIsNotNilAndParentHideOverrideIsTrue() {
        // Given
        let childOverrides: Overrides = .mockRandom()
        childOverrides.hide = false
        let parentOverrides: Overrides = .mockRandom()
        parentOverrides.hide = true

        // When
        let merged = SessionReplayOverrides.merge(childOverrides, with: parentOverrides)

        // Then
        XCTAssertEqual(merged.textAndInputPrivacy, childOverrides.textAndInputPrivacy)
        XCTAssertEqual(merged.imagePrivacy, childOverrides.imagePrivacy)
        XCTAssertEqual(merged.touchPrivacy, childOverrides.touchPrivacy)
        XCTAssertEqual(merged.hide, true)
    }
}
#endif
