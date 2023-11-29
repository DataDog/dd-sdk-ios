/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities
@testable import DatadogSessionReplay

extension EnrichedResource: RandomMockable {
    public static func mockRandom() -> Self {
        return .init(
            identifier: .mockRandom(),
            data: .mockRandom(),
            context: .mockRandom()
        )
    }
}

extension EnrichedResource.Context: RandomMockable {
    public static func mockRandom() -> Self {
        return .init(
            .mockRandom()
        )
    }
}
