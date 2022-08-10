/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import CoreGraphics

extension CGFloat: AnyMockable, RandomMockable {
    static func mockAny() -> CGFloat {
        return 42
    }

    static func mockRandom() -> CGFloat {
        return mockRandom(min: .leastNormalMagnitude, max: .greatestFiniteMagnitude)
    }

    static func mockRandom(min: CGFloat, max: CGFloat) -> CGFloat {
        return .random(in: min...max)
    }
}

extension CGRect: AnyMockable, RandomMockable {
    static func mockAny() -> CGRect {
        return .init(x: 0, y: 0, width: 400, height: 200)
    }

    static func mockRandom() -> CGRect {
        return .init(
            x: .mockRandom(min: -1_000, max: 1_000),
            y: .mockRandom(min: -1_000, max: 1_000),
            width: .mockRandom(min: 0, max: 1_000),
            height: .mockRandom(min: 0, max: 1_000)
        )
    }
}
