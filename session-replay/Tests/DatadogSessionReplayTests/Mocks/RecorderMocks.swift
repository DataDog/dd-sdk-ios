/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import DatadogSessionReplay

// MARK: - Equatable conformances

extension ViewTreeSnapshot: EquatableInTests {}

// MARK: - Mocking extensions

extension ViewTreeSnapshot: AnyMockable, RandomMockable {
    static func mockAny() -> ViewTreeSnapshot {
        return mockWith()
    }

    static func mockRandom() -> ViewTreeSnapshot {
        return mockWith(
            date: .mockRandom()
        )
    }

    static func mockWith(
        date: Date = .mockAny()
    ) -> ViewTreeSnapshot {
        return ViewTreeSnapshot(
            date: date
        )
    }
}
