/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
@testable import Datadog

/*
A collection of mocks for `DDSpan` objects.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension DDSpan {
    static func mockAny() -> DDSpan {
        return mockWith()
    }

    static func mockWith(
        tracer: DDTracer = .mockNoOp(),
        operationName: String = .mockAny(),
        parentSpanContext: DDSpanContext? = nil,
        tags: [String: Codable] = [:],
        startTime: Date = .mockAny()
    ) -> DDSpan {
        return DDSpan(
            tracer: tracer,
            operationName: operationName,
            parentSpanContext: parentSpanContext,
            tags: tags,
            startTime: startTime
        )
    }
}
