/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogRUM
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

extension DDColor: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        return DDColor.green as! Self
    }

    public static func mockRandom() -> Self {
        return mockRandomWith(alpha: .mockRandom(min: 0, max: 1))
    }

    public static func mockRandomWith(alpha: CGFloat) -> Self {
        return DDColor(
            red: .mockRandom(min: 0, max: 1),
            green: .mockRandom(min: 0, max: 1),
            blue: .mockRandom(min: 0, max: 1),
            alpha: alpha
        ) as! Self
    }
}
