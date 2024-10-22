//
//  PrivacyOverridesMock+objc.swift
//  DatadogSessionReplayTests iOS
//
//  Created by Marie Denis on 22/10/2024.
//  Copyright © 2024 Datadog. All rights reserved.
//

import Foundation
@_spi(objc)
import DatadogSessionReplay
import TestUtilities

extension objc_TextAndInputPrivacyLevelOverride: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return .maskSensitiveInputs
    }

    public static func mockRandom() -> Self {
        return [.maskAll, .maskAllInputs, .maskSensitiveInputs].randomElement()!
    }
}

extension objc_ImagePrivacyLevelOverride: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return .maskNonBundledOnly
    }

    public static func mockRandom() -> Self {
        return [.maskAll, .maskNonBundledOnly, .maskNone].randomElement()!
    }
}

extension objc_TouchPrivacyLevelOverride: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return .show
    }

    public static func mockRandom() -> Self {
        return [.show, .hide].randomElement()!
    }
}

extension NSNumber {
    static func mockAnyHidePrivacy() -> NSNumber? {
        return NSNumber(value: true)
    }

    static func mockRandomHidePrivacy() -> NSNumber? {
        return [true, false].randomElement().map { NSNumber(value: $0) } ?? nil
    }
}
