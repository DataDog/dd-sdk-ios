/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal

extension UserConfigurationContext: AnyMockable, RandomMockable {
    public static func mockAny() -> Self { mockWith() }

    public static func mockRandom() -> Self {
        .init(
            anonymousId: .mockRandom(),
            id: .mockRandom(),
            name: .mockRandom(),
            email: .mockRandom()
        )
    }

    public static func mockWith(
        anonymousId: String? = .mockAny(),
        id: String? = .mockAny(),
        name: String? = .mockAny(),
        email: String? = .mockAny()
    ) -> Self {
        .init(
            anonymousId: anonymousId,
            id: id,
            name: name,
            email: email
        )
    }
}
