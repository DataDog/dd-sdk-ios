/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Passes every sample through unchanged. Represents the baseline pipeline behaviour with no sampling strategy applied.
public final class PassThroughFilter: SampleFilter {
    public init() {}

    public func process(_ sample: Sample) -> [Sample] {
        return [sample]
    }

    public func flush() -> [Sample] {
        return []
    }
}
