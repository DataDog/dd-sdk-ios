/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Provides the correct sampler that should be used by the Tracer.
///
/// When RUM is active, Trace should use RUM's deterministic sampler, based on a session ID.
/// Since this can change during SDK setup and app lifecycle, providing the correct sampler must
/// be a dynamic operation.
///
/// Trace code that requires sampling should never create a custom sampler. Instead, use the
/// functions below for either obtaining the default sampler or creating one for a custom sampling
/// rate.
internal protocol TracerSamplerProvider {
    /// Obtains the sampler that should be used for Trace sampling operations.
    ///
    /// Depending on the runtime situation, this can either be a deterministic sampler, consistent
    /// with RUM, or a random-based sampler. Do not make assumptions about the type of sampler
    /// obtained here.
    ///
    /// The returned sampler must have the sampling rate set in the Trace feature configuration.
    ///
    /// - Important: The implementation **must** be thread-safe, since this will be called
    /// from multiple threads.
    var sampler: Sampling { get }

    /// Creates a sampler with a custom sampling rate.
    ///
    /// For operations that require a sampling rate different than the default one (defined in
    /// the Trace feature configuration), use this function to create a sampler. The returned
    /// sampler will depend on the runtime situation, this can either be a deterministic sampler,
    /// consistent with RUM, or a random-based sampler. Do not make assumptions about
    /// the type of sampler obtained here.
    ///
    /// - Important: The implementation **must** be thread-safe, since this will be called
    /// from multiple threads.
    ///
    /// - parameters:
    ///   - samplingRate: The desired sampling rate (between 0 and 100).
    ///
    /// - returns: The appropriate sampler to be used for tracing operations with custom
    /// sampling rates.
    func makeSamplerFor(samplingRate: SampleRate) -> Sampling
}
