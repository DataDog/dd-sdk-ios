/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

@testable import Datadog

extension TracingUUID: ExpressibleByIntegerLiteral {
    public typealias IntegerLiteralType = UInt64

    public init(integerLiteral value: UInt64) {
        self.init(rawValue: value)
    }
}
