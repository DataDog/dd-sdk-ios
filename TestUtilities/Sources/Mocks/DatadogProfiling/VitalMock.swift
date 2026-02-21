/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

extension Vital: AnyMockable, RandomMockable {
    public static func mockAny() -> Self {
        mockWith()
    }

    public static func mockRandom() -> Self {
        mockWith(
            id: .mockRandom(),
            name: .mockRandom(),
            operationKey: .mockRandom(),
            type: [VitalType.duration, .applicationLaunch, .rumOperation(.start)].randomElement()!,
            date: .mockRandom(),
            duration: .mockRandom()
        )
    }

    public static func mockWith(
        id: String = .mockAny(),
        name: String = .mockAny(),
        operationKey: String? = .mockAny(),
        type: VitalType = .duration,
        date: Date = .mockAny(),
        duration: Int64 = .mockAny()
    ) -> Self {
        .init(id: id, name: name, operationKey: operationKey, type: type, date: date, duration: duration)
    }
}
