/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

public internal(set) var defaultDatadogCore: DatadogCoreProtocol = NOOPDatadogCore()

/// A Datadog Core holds a set of features and is responsible of managing their storage
/// and upload mechanism. It also provides a thread-safe scope for writing events.
public protocol DatadogCoreProtocol {
}

/// Provide feature specific storage configuration.
internal struct FeatureStorageConfiguration {
    /// A set of paths for managing persisted data for this Feature.
    /// Each path is relative to the root folder of given SDK instance.
    struct Directories {
        /// The path for writing authorized data (when tracking consent is granted).
        /// This path must be relative to the core directory created for given instance of the SDK.
        let authorized: String
        /// The path for writing unauthorized data (when tracking consent is pending).
        /// This path must be relative to the core directory created for given instance of the SDK.
        let unauthorized: String
    }

    /// Directories storing data for this Feature.
    let directories: Directories

    // MARK: - V1 interface

    /// A human-readable name of this Feature used for naming internal queues specific to this Feature and annotating
    /// origin of telemetry and verbosity logs produced by the SDK.
    let featureName: String
}

/// A datadog feature providing thread-safe scope for writing events.
public protocol FeatureScope {
    // TODO: RUMM-2133
}

/// No-op implementation of `DatadogFeatureRegistry`.
internal struct NOOPDatadogCore: DatadogCoreProtocol {
}
