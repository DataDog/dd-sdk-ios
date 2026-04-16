/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A stateful filter that processes samples from a provider before they are forwarded to the batcher.
///
/// Filters are class-only (reference semantics) because they maintain internal state across calls.
public protocol SampleFilter: AnyObject {
    /// Called for each sample emitted by the provider.
    ///
    /// - Parameter sample: The incoming sample to process.
    /// - Returns: The samples to forward to the batcher. Return an empty array to suppress the sample,
    ///   return `[sample]` to forward it unchanged, or return multiple samples to expand it.
    func process(_ sample: Sample) -> [Sample]

    /// Called once when the provider is exhausted, signalling end-of-stream.
    ///
    /// Use this method to flush any internally buffered samples that have not yet been forwarded.
    /// Most filters return an empty array here. Aggregating filters (e.g. `WindowAggregateFilter`)
    /// use this to emit the final partial window that would otherwise be held back.
    ///
    /// - Returns: Any remaining samples that should be forwarded to the batcher.
    func flush() -> [Sample]
}
