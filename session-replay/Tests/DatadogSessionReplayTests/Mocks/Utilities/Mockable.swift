/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// A type that can produce **any** mock value.
/// Should be used to indicate that tested behaviour of SUT does not depend on this value.
protocol AnyMockable {
    static func mockAny() -> Self
}

/// A type that can produce **random** mock value.
/// Should be used for fuzzy testing and asserting that tested behaviour of SUT depends on this value.
protocol RandomMockable {
    static func mockRandom() -> Self
}

extension Array: AnyMockable where Element: AnyMockable {
    static func mockAny() -> [Element] {
        return mockAny(count: 10)
    }

    static func mockAny(count: Int) -> [Element] {
        return (0..<count).map { _ in .mockAny() }
    }
}

extension Array: RandomMockable where Element: RandomMockable {
    static func mockRandom() -> [Element] {
        return mockRandom(count: .random(in: 0..<100))
    }

    static func mockRandom(count: Int) -> [Element] {
        return (0..<count).map { _ in .mockRandom() }
    }
}
