/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import DatadogSessionReplay
import TestUtilities

extension ImagePrivacyLevel: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        .maskNonBundledImages
    }

    public static func mockRandom() -> Self {
        [.maskNonBundledImages, .maskAll, .maskNone].randomElement()!
    }
}
#endif
