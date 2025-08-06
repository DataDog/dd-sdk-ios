//
//  AccountConfigurationContextMocks.swift
//  Datadog
//
//  Created by Valentin Pertuisot on 05/08/2025.
//  Copyright © 2025 Datadog. All rights reserved.
//

import DatadogInternal

extension AccountConfigurationContext: AnyMockable, RandomMockable {

    public static func mockAny() -> Self { mockWith() }

    public static func mockRandom() -> Self {
        .init(
            id: .mockRandom(),
            name: .mockRandom()
        )
    }

    public static func mockWith(
        id: String = .mockAny(),
        name: String? = .mockAny(),
    ) -> Self {
        .init(
            id: id,
            name: name,
        )
    }
}
