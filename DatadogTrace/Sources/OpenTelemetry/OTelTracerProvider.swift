/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import Foundation
import DatadogInternal
import OpenTelemetryApi

/// The Datadog implementation of OpenTelemetry `TracerProvider`.
/// It takes the Datadog SDK instance as a dependency and returns the tracer from it.
///
/// Usage:
///
/// ```swift
/// import OpenTelemetryApi
/// import DatadogTrace
///
/// // Register the tracer provider
/// OpenTelemetry.registerTracerProvider(
///     tracerProvider: OTelTracerProvider()
/// )
///
/// // Get the tracer
/// let tracer = OpenTelemetry
///     .instance
///     .tracerProvider
///     .get(instrumentationName: "", instrumentationVersion: nil)
///
/// // Start a span
/// let span = tracer
///     .spanBuilder(spanName: "OperationName")
///     .startSpan()
/// ```
public class OTelTracerProvider: OpenTelemetryApi.TracerProvider {
    private weak var core: DatadogCoreProtocol?

    /// Creates a tracer provider with the given Datadog SDK instance.
    /// - Parameter core: the instance of Datadog SDK the Trace feature was enabled in (global instance by default)
    public init(in core: DatadogCoreProtocol = CoreRegistry.default) {
        self.core = core
    }

    /// Returns a tracer with the given instrumentation name and version.
    /// - Parameters:
    ///   - instrumentationName: the name of the instrumentation library, not the name of the instrumented library
    ///     Note: This is ignored, as the Datadog SDK works on concept of core.
    ///   - instrumentationVersion:  The version of the instrumentation library (e.g., "semver:1.0.0"). Optional
    ///     Note: This is ignored, as the Datadog SDK works on concept of core.
    public func get(instrumentationName: String, instrumentationVersion: String?) -> OpenTelemetryApi.Tracer {
        do {
            guard !(core is NOPDatadogCore) else {
                throw ProgrammerError(
                    description: "Datadog SDK must be initialized and RUM feature must be enabled before calling `OTelTracerProvider.get(instrumentationName:instrumentationVersion:)`."
                )
            }
            guard let feature = core?.get(feature: TraceFeature.self) else {
                throw ProgrammerError(
                    description: "Trace feature must be enabled before calling `OTelTracerProvider.get(instrumentationName:instrumentationVersion:)`."
                )
            }

            return feature.tracer
        } catch {
            consolePrint("\(error)", .error)
            return DDNoopTracer()
        }
    }
}
