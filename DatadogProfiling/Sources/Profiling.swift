/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal)
import DatadogInternal

#if !os(watchOS)

// swiftlint:disable duplicate_imports
#if swift(>=6.0)
internal import DatadogMachProfiler
#else
@_implementationOnly import DatadogMachProfiler
#endif
// swiftlint:enable duplicate_imports

/// Main entry point for Datadog profiling functionality.
///
/// The `Profiling` provides static methods to configure, enable profiling.
/// It captures performance data in pprof format and sends it to Datadog for analysis.
public enum Profiling {
    /// Enables profiling with the specified configuration.
    /// 
    /// This method registers the profiling feature with the Datadog core, setting up
    /// the necessary components.
    ///
    /// Profiling supports only one SDK instance. Later calls are ignored with a warning
    /// identifying the instance where Profiling is already enabled.
    /// 
    /// - Parameters:
    ///   - configuration: The profiling configuration to use.
    ///   - core: The Datadog core instance to register with. Defaults to the default core.
    @available(*, message: "This API is experimental and may change in future releases")
    public static func enable(with configuration: Configuration = .init(), in core: DatadogCoreProtocol = CoreRegistry.default) {
        do {
            // To ensure the correct registration order between Core and Features,
            // the entire initialization flow is synchronized on the main thread.
            try runOnMainThreadSync {
                try enableOrThrow(with: configuration, in: core)
            }
        } catch let error {
            consolePrint("\(error)", .error)
        }
    }

    internal static func enableOrThrow(with configuration: Configuration, in core: DatadogCoreProtocol) throws {
        guard !(core is NOPDatadogCore) else {
            throw ProgrammerError(
                description: "Datadog SDK must be initialized before calling `Profiling.enable(with:)`."
            )
        }

        if let instanceName = CoreRegistry.instanceName(for: ProfilerFeature.self) {
            core.telemetry.debug("Profiling has already been enabled in SDK instance '\(instanceName)'")
            throw ProgrammerError(
                description: "Profiling is already enabled in SDK instance '\(instanceName)' " +
                "and does not support multiple instances. " +
                "The existing instance will continue to be used."
            )
        }

        let telemetryController = ProfilingTelemetryController(
            sampleRate: configuration.debugSDK ? 100 : ProfilingTelemetryController.defaultSampleRate,
            telemetry: core.telemetry
        )
        try? core.register(
            feature: ProfilerFeature(
                core: core,
                configuration: configuration,
                requestBuilder: RequestBuilder(
                    customUploadURL: configuration.customEndpoint,
                    telemetry: core.telemetry
                ),
                telemetryController: telemetryController
            )
        )

        core.set(context: ProfilingContext(status: .current))
    }
}

#endif
