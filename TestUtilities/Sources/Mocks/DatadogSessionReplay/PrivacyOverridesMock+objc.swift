/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation
@_spi(objc)
@testable import DatadogSessionReplay

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
    public static func mockRandomBoolean() -> NSNumber? {
        NSNumber(value: [true, false].randomElement()!)
    }
}
#endif
