/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension DDError: AnyMockable, RandomMockable {
    public static func mockAny() -> DDError {
        return DDError(
            type: .mockAny(),
            message: .mockAny(),
            stack: .mockAny()
        )
    }

    public static func mockRandom() -> DDError {
        return DDError(
            type: .mockRandom(),
            message: .mockRandom(),
            stack: .mockRandom()
        )
    }
}
