/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if os(iOS)

import Foundation

@_spi(Internal)
public extension Int64 {
    static func positiveRandom<T>(using generator: inout T) -> Int64 where T: RandomNumberGenerator {
        .random(in: 0..<Int64.max, using: &generator)
    }
}

#endif
