/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)
import Foundation
@testable import DatadogSessionReplay

extension EnrichedResource: RandomMockable, AnyMockable {
    public static func mockAny() -> EnrichedResource {
        return .init(
            identifier: .mockAny(),
            data: .mockAny(),
            mimeType: .mockAny(),
            context: .mockAny()
        )
    }

    public static func mockWith(
        identifier: String = .mockAny(),
        data: Data = .mockAny(),
        mimeType: String = .mockAny(),
        context: Context = .mockAny()
    ) -> EnrichedResource {
        return .init(
            identifier: identifier,
            data: data,
            mimeType: mimeType,
            context: context
        )
    }

    public static func mockRandom() -> Self {
        return .init(
            identifier: .mockRandom(),
            data: .mockRandom(),
            mimeType: "image/png",
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
#endif
