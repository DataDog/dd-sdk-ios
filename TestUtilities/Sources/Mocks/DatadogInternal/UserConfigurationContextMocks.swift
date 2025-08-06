//
//  UserConfigurationContextMocks.swift
//  Datadog
//
//  Created by Valentin Pertuisot on 05/08/2025.
//  Copyright © 2025 Datadog. All rights reserved.
//

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
