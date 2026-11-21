/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

#if !os(watchOS) && !os(macOS)

/// Configuration options for the profiling feature.
@objc(DDProfilingConfiguration)
@objcMembers
@_spi(objc)
public final class objc_ProfilingConfiguration: NSObject {
    internal var configuration: Profiling.Configuration

    /// Overrides the server endpoint where profiles are sent.
    ///
    /// Default: `nil`, which uses the Datadog endpoint.
    public var customEndpoint: URL? {
        get { configuration.customEndpoint }
        set { configuration.customEndpoint = newValue }
    }

    /// The sampling rate for App Launch Profiling, between 0 and 100.
    ///
    /// Applies to the next process launch. Default: `5.0`.
    public var applicationLaunchSampleRate: Float {
        get { configuration.applicationLaunchSampleRate }
        set { configuration.applicationLaunchSampleRate = newValue }
    }

    /// The sampling rate for Continuous Profiling, between 0 and 100.
    ///
    /// Applied in addition to the RUM session sample rate. Default: `5.0`.
    public var continuousSampleRate: Float {
        get { configuration.continuousSampleRate }
        set { configuration.continuousSampleRate = newValue }
    }

    /// Creates a profiling configuration with default values.
    override public init() {
        configuration = .init()
    }

    /// Creates a profiling configuration.
    ///
    /// - Parameters:
    ///   - customEndpoint: Overrides the server endpoint where profiles are sent.
    ///   - applicationLaunchSampleRate: The sampling rate for App Launch Profiling.
    ///   - continuousSampleRate: The sampling rate for Continuous Profiling.
    public init(
        customEndpoint: URL? = nil,
        applicationLaunchSampleRate: Float = 5,
        continuousSampleRate: Float = 5
    ) {
        configuration = .init(
            customEndpoint: customEndpoint,
            applicationLaunchSampleRate: applicationLaunchSampleRate,
            continuousSampleRate: continuousSampleRate
        )
    }
}

/// An entry point to the profiling feature.
@objc(DDProfiling)
@objcMembers
@_spi(objc)
public final class objc_Profiling: NSObject {
    override private init() { }

    /// Enables profiling on the default SDK instance.
    ///
    /// Initialize the SDK before calling this method. Profiling supports only one SDK instance;
    /// later calls are ignored with a warning identifying the instance where it is already enabled.
    /// - Parameter configuration: The profiling configuration.
    public static func enable(with configuration: objc_ProfilingConfiguration = .init()) {
        Profiling.enable(with: configuration.configuration)
    }

    /// Enables profiling on a named SDK instance.
    ///
    /// Profiling supports only one SDK instance; later calls keep the existing feature active.
    /// - Parameters:
    ///   - configuration: The profiling configuration.
    ///   - instanceName: The SDK instance name, or `nil` for the default instance.
    public static func enable(with configuration: objc_ProfilingConfiguration, instanceName: String?) {
        Profiling.enable(
            with: configuration.configuration,
            in: CoreRegistry.instance(named: instanceName ?? CoreRegistry.defaultInstanceName)
        )
    }
}

#endif
