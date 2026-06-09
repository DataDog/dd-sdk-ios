/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Provides the last successfully fetched remote configuration.
public protocol RemoteConfigurationProvider {
    /// The last successfully fetched and decoded remote configuration, if any.
    var remoteConfiguration: RemoteConfiguration? { get }
}

/// Default implementation that returns no remote configuration.
public struct DefaultRemoteConfigurationProvider: RemoteConfigurationProvider {
    public init() { }

    public var remoteConfiguration: RemoteConfiguration? { nil }
}
