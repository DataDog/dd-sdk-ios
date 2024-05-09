/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import TestUtilities

@testable import DatadogSessionReplay

extension RUMContext: AnyMockable, RandomMockable {
    public static func mockAny() -> RUMContext {
        return .mockWith()
    }

    public static func mockRandom() -> RUMContext {
        return RUMContext(
            applicationID: .mockRandom(),
            sessionID: .mockRandom(),
            viewID: .mockRandom(),
            viewServerTimeOffset: .mockRandom()
        )
    }

    static func mockWith(
        applicationID: String = .mockAny(),
        sessionID: String = .mockAny(),
        viewID: String? = .mockAny(),
        serverTimeOffset: TimeInterval = .mockAny()
    ) -> RUMContext {
        return RUMContext(
            applicationID: applicationID,
            sessionID: sessionID,
            viewID: viewID,
            viewServerTimeOffset: serverTimeOffset
        )
    }
}
