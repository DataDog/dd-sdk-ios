/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension Sampler: AnyMockable, RandomMockable {
    public static func mockAny() -> Sampler {
        return .init(samplingRate: 50)
    }

    public static func mockRandom() -> Sampler {
        return .init(samplingRate: .random(in: (0.0...100.0)))
    }

    public static func mockKeepAll() -> Sampler {
        return .init(samplingRate: 100)
    }

    public static func mockRejectAll() -> Sampler {
        return .init(samplingRate: 0)
    }
}
