/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
@testable import DatadogCore

extension DatadogContextProvider: AnyMockable {
    public static func mockAny() -> Self { .mockWith() }

    public static func mockWith(context: DatadogContext = .mockAny()) -> Self {
        .init(context: context)
    }
}
