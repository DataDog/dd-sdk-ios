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
        XCTAssertNil(view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy)
        XCTAssertNil(view.dd.sessionReplayPrivacyOverrides.imagePrivacy)
        XCTAssertNil(view.dd.sessionReplayPrivacyOverrides.touchPrivacy)
        XCTAssertNil(view.dd.sessionReplayPrivacyOverrides.hide)
    }

    func testWithOverrides() {
        // Given
        let view = UIView()

        // When
        view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = .maskAllInputs
        view.dd.sessionReplayPrivacyOverrides.imagePrivacy = .maskAll
        view.dd.sessionReplayPrivacyOverrides.touchPrivacy = .hide
        view.dd.sessionReplayPrivacyOverrides.hide = true

        // Then
        XCTAssertEqual(view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy, .maskAllInputs)
        XCTAssertEqual(view.dd.sessionReplayPrivacyOverrides.imagePrivacy, .maskAll)
        XCTAssertEqual(view.dd.sessionReplayPrivacyOverrides.touchPrivacy, .hide)
        XCTAssertEqual(view.dd.sessionReplayPrivacyOverrides.hide, true)
    }

    func testRemovingOverrides() {
        // Given
        let view = UIView()
        view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = .maskAllInputs
        view.dd.sessionReplayPrivacyOverrides.imagePrivacy = .maskAll
        view.dd.sessionReplayPrivacyOverrides.touchPrivacy = .hide
        view.dd.sessionReplayPrivacyOverrides.hide = true

        // When
        view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = nil
        view.dd.sessionReplayPrivacyOverrides.imagePrivacy = nil
        view.dd.sessionReplayPrivacyOverrides.touchPrivacy = nil
        view.dd.sessionReplayPrivacyOverrides.hide = nil

        // Then
        XCTAssertNil(view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy)
        XCTAssertNil(view.dd.sessionReplayPrivacyOverrides.imagePrivacy)
        XCTAssertNil(view.dd.sessionReplayPrivacyOverrides.touchPrivacy)
        XCTAssertNil(view.dd.sessionReplayPrivacyOverrides.hide)
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
        let overrides: PrivacyOverrides = .mockRandom()

        let childOverrides: PrivacyOverrides = .mockAny()
        childOverrides.textAndInputPrivacy = overrides.textAndInputPrivacy
        // We set the `hide` override on the child because in the merge process,
        // the child's override takes precedence. If the parent's `hide` is `false`,
        // the final merged value will end up as `nil`, which makes the test fail.
        childOverrides.hide = overrides.hide

        let parentOverrides: PrivacyOverrides = .mockAny()
        parentOverrides.imagePrivacy = overrides.imagePrivacy
        parentOverrides.touchPrivacy = overrides.touchPrivacy

        // When
        let merged = SessionReplayPrivacyOverrides.merge(childOverrides, with: parentOverrides)

        // Then
        XCTAssertEqual(merged.textAndInputPrivacy, overrides.textAndInputPrivacy)
        XCTAssertEqual(merged.imagePrivacy, overrides.imagePrivacy)
        XCTAssertEqual(merged.touchPrivacy, overrides.touchPrivacy)
        XCTAssertEqual(merged.touchPrivacy, overrides.touchPrivacy)
    }

    func testMergeWithNilParentOverrides() {
        // Given
        let childOverrides: PrivacyOverrides = .mockRandom()
        let parentOverrides: PrivacyOverrides = .mockAny()

        // When
        let merged = SessionReplayPrivacyOverrides.merge(childOverrides, with: parentOverrides)

        // Then
        XCTAssertEqual(merged.textAndInputPrivacy, childOverrides.textAndInputPrivacy)
        XCTAssertEqual(merged.imagePrivacy, childOverrides.imagePrivacy)
        XCTAssertEqual(merged.touchPrivacy, childOverrides.touchPrivacy)
        XCTAssertEqual(merged.hide, childOverrides.hide)
    }

    func testMergeWithNilChildOverrides() {
        // Given
        let childOverrides: PrivacyOverrides = .mockAny()
        let parentOverrides: PrivacyOverrides = .mockRandom()
        /// We explicitly set `hide` to `true` in the parent override because the child’s `hide` is `nil`.
        /// In the merge logic, `true` takes precedence, and `false` behaves the same as `nil`, meaning no override.
        parentOverrides.hide = true

        // When
        let merged = SessionReplayPrivacyOverrides.merge(childOverrides, with: parentOverrides)

        // Then
        XCTAssertEqual(merged.textAndInputPrivacy, parentOverrides.textAndInputPrivacy)
        XCTAssertEqual(merged.imagePrivacy, parentOverrides.imagePrivacy)
        XCTAssertEqual(merged.touchPrivacy, parentOverrides.touchPrivacy)
        XCTAssertEqual(merged.hide, parentOverrides.hide)
    }

    func testMergeWhenChildHideOverrideIsNotNilAndParentHideOverrideIsTrue() {
        // Given
        let childOverrides: PrivacyOverrides = .mockRandom()
        childOverrides.hide = false
        let parentOverrides: PrivacyOverrides = .mockRandom()
        parentOverrides.hide = true

        // When
        let merged = SessionReplayPrivacyOverrides.merge(childOverrides, with: parentOverrides)

        // Then
        XCTAssertEqual(merged.textAndInputPrivacy, childOverrides.textAndInputPrivacy)
        XCTAssertEqual(merged.imagePrivacy, childOverrides.imagePrivacy)
        XCTAssertEqual(merged.touchPrivacy, childOverrides.touchPrivacy)
        XCTAssertEqual(merged.hide, true)
    }
}
#endif
