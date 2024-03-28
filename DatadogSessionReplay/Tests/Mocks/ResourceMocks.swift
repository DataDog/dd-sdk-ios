/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities
@testable import DatadogSessionReplay

extension EnrichedResource: RandomMockable, AnyMockable {
    public static func mockAny() -> EnrichedResource {
        return .init(
            identifier: .mockAny(),
            data: .mockAny(),
            context: .mockAny()
        )
    }

    public static func mockWith(
        identifier: String = .mockAny(),
        data: Data = .mockAny(),
        context: Context = .mockAny()
    ) -> EnrichedResource {
        return .init(
            identifier: identifier,
            data: data,
            context: context
        )
    }

    public static func mockRandom() -> Self {
        return .init(
            identifier: .mockRandom(),
            data: .mockRandom(),
            context: .mockRandom()
        )
    }
}

extension EnrichedResource.Context: RandomMockable, AnyMockable {
    public static func mockAny() -> DatadogSessionReplay.EnrichedResource.Context {
        return .init(
            .mockAny()
        )
    }

    public static func mockRandom() -> Self {
        return .init(
            .mockRandom()
        )
    }
}
