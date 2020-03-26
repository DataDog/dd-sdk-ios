/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import XCTest
@testable import Datadog

/*
A collection of SDK object mocks for Tracing.
It follows the mocking conventions described in `FoundationMocks.swift`.
 */

extension TracingUUID {
    static func mockAny() -> TracingUUID {
        return .generateUnique()
    }

    static func mock(_ rawValue: UInt64) -> TracingUUID {
        return TracingUUID(rawValue: rawValue)
    }
}

extension DDTracer {
    static func mockNoOp() -> DDTracer {
        return DDTracer()
    }
}
