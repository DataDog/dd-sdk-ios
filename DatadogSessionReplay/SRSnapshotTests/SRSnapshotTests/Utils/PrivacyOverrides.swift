/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit
@testable import DatadogSessionReplay

// MARK: PrivacyTag
/// Represents different types of privacy settings that can be applied at the view-level in snapshot tests.
/// Each case in `PrivacyTag` holds a view tag and defines a specific override to be applied.
/// This enum abstracts away the specific privacy level implementation within snapshot tests.
///
/// Usage examples:
/// - `.hideView(tag: 1)` applies a privacy setting to hide the view with the specified tag.
/// - `.maskAllText(tag: 2)` applies a privacy setting to mask all text elements in the view with the specified tag.

enum PrivacyTag {
    case maskAllText(tag: Int)
    case unmaskText(tag: Int)
    case maskAllImages(tag: Int)
    case maskNonBundledImages(tag: Int)
    case unmaskImages(tag: Int)
    case hideView(tag: Int)

    var tag: Int {
        switch self {
        case .maskAllText(let tag),
             .unmaskText(let tag),
             .maskAllImages(let tag),
             .maskNonBundledImages(let tag),
             .unmaskImages(let tag),
             .hideView(let tag):
            return tag
        }
    }
}

extension PrivacyTag {
    func createPrivacyApplier() -> PrivacyTagApplier {
        switch self {
        case .maskAllText:
            return TextAndInputPrivacyLevel.maskAll
        case .unmaskText:
            return TextAndInputPrivacyLevel.maskSensitiveInputs
        case .maskAllImages:
            return ImagePrivacyLevel.maskAll
        case .maskNonBundledImages:
            return ImagePrivacyLevel.maskNonBundledOnly
        case .unmaskImages:
            return ImagePrivacyLevel.maskNone
        case .hideView:
            return HiddenPrivacy(hide: true)
        }
    }
}


// MARK: Privacy Override Protocol
protocol PrivacyTagApplier {
    func apply(to view: UIView)
}

extension TextAndInputPrivacyLevel: PrivacyTagApplier {
    func apply(to view: UIView) {
        view.dd.sessionReplayPrivacyOverrides.textAndInputPrivacy = self
    }
}

extension ImagePrivacyLevel: PrivacyTagApplier {
    func apply(to view: UIView) {
        view.dd.sessionReplayPrivacyOverrides.imagePrivacy = self
    }
}

// Wrapper for the Hidden Privacy Override,
// which is a `Bool` and not an `enum` like others
struct HiddenPrivacy: PrivacyTagApplier {
    let hide: Bool

    func apply(to view: UIView) {
        view.dd.sessionReplayPrivacyOverrides.hide = hide
    }
}
