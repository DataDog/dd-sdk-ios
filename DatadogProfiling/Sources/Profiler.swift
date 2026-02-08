/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// A class for manual interaction with the Profiling feature. It records profiles that are sent to Datadog Profiling.
///
/// There can be only one active Profiler for certain instance of Datadog SDK. It gets enabled along with
/// the call to `Profiling.enable(with:in:)`:
///
///     import DatadogProfiling
///
///     // Enable Profiling feature:
///     Profiling.enable(with: configuration)
///
///     // Use Profiler:
///     Profiler.shared().start(...)
///
public class Profiler {
    /// Obtains the Profiler for manual profiling instrumentation.
    ///
    /// It requires `Profiling.enable(with:in:)` to be called first - otherwise it will return no-op implementation.
    /// - Parameter core: the instance of Datadog SDK the Profiling feature was enabled in (global instance by default)
    /// - Returns: the Profiler
    public static func shared(in core: DatadogCoreProtocol = CoreRegistry.default) -> CustomProfiler {
        do {
            guard !(core is NOPDatadogCore) else {
                throw ProgrammerError(
                    description: "Datadog SDK must be initialized and Profiling feature must be enabled before calling `Profiler.shared(in:)`."
                )
            }
            guard let feature = core.get(feature: ProfilerFeature.self) else {
                throw ProgrammerError(
                    description: "Profiling feature must be enabled before calling `Profiler.shared(in:)`."
                )
            }

            return feature.customProfiler
        } catch {
            consolePrint("\(error)", .error)
            return DDNoopProfiler()
        }
    }
}

public protocol CustomProfiler {
    /// Starts a profiling session.
    ///
    /// Begins capturing performance data using the configured profiler. The session
    /// will continue until `stop()` is called.
    ///
    /// - Parameters:
    ///   - name: the name of the profiling operation (e.g., `login_flow`)
    ///   - operationKey: the key of the operation for this step (when running several instances of the same operation)
    ///   - currentThreadOnly: If `true`, profiles only the current thread.
    ///   - attributes: custom attributes to attach to this operation
    ///   - sampleRate: The sample rate . Defaults to the default core.
    func start(
        name: String,
        operationKey: String?,
        currentThreadOnly: Bool,
        attributes: [AttributeKey: AttributeValue],
        sampleRate: SampleRate
    )

    /// Stops the Profiling session.
    /// - Parameters:
    ///   - name: the name of the operation (e.g., `login_flow`)
    ///   - operationKey: the key of the operation for this step (when running several instances of the same operation); it should be provided if `operationKey` was provided when invoking `startFeatureOperation`
    ///   - attributes: custom attributes to attach to this operation
    func stop(
        name: String,
        operationKey: String?,
        attributes: [AttributeKey: AttributeValue]
    )
}

internal class DDNoopProfiler: CustomProfiler {
    func start(
        name: String,
        operationKey: String?,
        currentThreadOnly: Bool,
        attributes: [AttributeKey: AttributeValue],
        sampleRate: SampleRate
    ) {
        warn()
    }

    func stop(
        name: String,
        operationKey: String?,
        attributes: [DatadogInternal.AttributeKey : any AttributeValue]
    ) {
        warn()
    }

    private func warn() {
        DD.logger.warn(
            """
            The `Profiler.shared()` was called but `Profiling` is not initialised. 
            Enable the `Profiling` feature before invoking `Profiler.shared()`
            """
        )
    }
}
