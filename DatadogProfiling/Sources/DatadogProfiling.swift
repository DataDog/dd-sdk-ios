/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Main entry point for Datadog profiling functionality.
/// 
/// The `Profiling` provides static methods to configure, enable, start, and stop
/// profiling sessions. It captures performance data in pprof format and sends it to
/// Datadog for analysis.
public enum Profiling {
    /// Configuration options for the profiling feature.
    public struct Configuration {
        /// Overrides the custom server endpoint where Profiles are sent.
        /// If `nil`, the default Datadog endpoint will be used.
        public var customEndpoint: URL?

        /// Creates a new profiling configuration.
        /// - Parameter customEndpoint: Optional custom server endpoint for profile uploads.
        public init(
            customEndpoint: URL? = nil
        ) {
            self.customEndpoint = customEndpoint
        }
    }

    /// Enables profiling with the specified configuration.
    /// 
    /// This method registers the profiling feature with the Datadog core, setting up
    /// the necessary components.
    /// 
    /// - Parameters:
    ///   - configuration: The profiling configuration to use.
    ///   - core: The Datadog core instance to register with. Defaults to the default core.
    public static func enable(with configuration: Configuration, in core: DatadogCoreProtocol = CoreRegistry.default) {
        try? core.register(
            feature: ProfilerFeature(
                profiler: MachProfiler(),
                requestBuilder: RequestBuilder(
                    customUploadURL: configuration.customEndpoint,
                    telemetry: core.telemetry
                ),
                messageReceiver: NOPFeatureMessageReceiver()
            )
        )
    }

    /// Starts a profiling session.
    /// 
    /// Begins capturing performance data using the configured profiler. The session
    /// will continue until `stop()` is called.
    /// 
    /// - Parameters:
    ///   - currentThreadOnly: If `true`, profiles only the current thread. Currently unused.
    ///   - core: The Datadog core instance to use. Defaults to the default core.
    public static func start(currentThreadOnly: Bool = false, in core: DatadogCoreProtocol = CoreRegistry.default) {
        core.get(feature: ProfilerFeature.self)?
            .profiler.start(currentThreadOnly: currentThreadOnly)
    }

    /// Stops the current profiling session and uploads the captured data.
    /// 
    /// This method stops the profiler, captures the performance data, creates a profile event
    /// with appropriate metadata (including RUM context if available), and sends it to Datadog.
    /// 
    /// - Parameter core: The Datadog core instance to use. Defaults to the default core.
    public static func stop(in core: DatadogCoreProtocol = CoreRegistry.default) {
        guard
            let feature = core.get(feature: ProfilerFeature.self),
            let profile = try? feature.profiler.stop()
        else {
            return
        }

        core.scope(for: ProfilerFeature.self).eventWriteContext { context, writer in
            var event = ProfileEvent(
                family: "ios",
                runtime: "ios",
                version: "4",
                start: profile.start,
                end: profile.end,
                attachments: [ProfileEvent.Constants.wallFilename],
                tags: [
                    "service:\(context.service)",
                    "version:\(context.version)",
                    "env:\(context.env)",
                    "source:\(context.source)",
                    "language:swift",
                    "format:pprof",
                    "remote_symbols:yes",
                ].joined(separator: ",")
            )

            if let rum = context.additionalContext(ofType: RUMCoreContext.self) {
                event.application = ProfileEvent.Application(id: rum.applicationID)
                event.session = ProfileEvent.Session(id: rum.sessionID)
                // Currently, link to the last view. But we should keep track of all views
                // while profiling and link a list.
                event.view = rum.viewID.map { ProfileEvent.Views(id: [$0]) }
            }

            writer.write(value: profile.pprof, metadata: event)
        }
    }
}
