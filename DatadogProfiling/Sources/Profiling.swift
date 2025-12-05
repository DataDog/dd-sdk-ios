/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

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
    /// - Parameters:
    ///   - configuration: The profiling configuration to use.
    ///   - core: The Datadog core instance to register with. Defaults to the default core.
    public static func enable(with configuration: Configuration = .init(), in core: DatadogCoreProtocol = CoreRegistry.default) {
        let telemetryController = ProfilingTelemetryController(
            sampleRate: configuration.debugSDK ? 100 : ProfilingTelemetryController.defaultSampleRate,
            telemetry: core.telemetry
        )
        try? core.register(
            feature: ProfilerFeature(
                requestBuilder: RequestBuilder(
                    customUploadURL: configuration.customEndpoint,
                    telemetry: core.telemetry
                ),
                messageReceiver: AppLaunchProfiler(telemetryController: telemetryController),
                sampleRate: configuration.debugSDK ? .maxSampleRate : configuration.sampleRate,
                telemetryController: telemetryController
            )
        )

        core.set(context: ProfilingContext(status: .current))
    }
}
