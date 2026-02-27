/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Represents the current state of a ``FlagsClient``.
///
/// The state transitions follow this lifecycle:
/// - Initial: ``notReady``
/// - On `setEvaluationContext()`: ``notReady`` → ``reconciling`` → ``ready`` / ``stale`` / ``error``
/// - On context change: ``ready`` or ``stale`` → ``reconciling`` → ``ready`` / ``stale`` / ``error``
/// - On `reset()`: any → ``notReady``
public enum FlagsClientState: Equatable {
    /// The client is not ready to evaluate flags.
    ///
    /// This state occurs before `setEvaluationContext()` is called or after `reset()`.
    /// No flags are available for evaluation.
    case notReady

    /// The client has successfully loaded flags and they are available for evaluation.
    case ready

    /// The client is currently fetching flags for a context change.
    /// Cached flags may still be available for evaluation during this state.
    case reconciling

    /// A network failure occurred but cached flags are still available for evaluation.
    ///
    /// Flag evaluations will return previously cached values, which may be outdated.
    case stale

    /// An unrecoverable error occurred and no flags are available for evaluation.
    case error
}
