/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if OTEL_API
#error("Benchmarks depends on opentelemetry-swift. Please open the project with 'make benchmark-tests-open'.")
#endif

import Foundation
import OpenTelemetryApi
import OpenTelemetrySdk
import DatadogExporter

/// Benchmark entrypoint to configure opentelemetry with metrics meters
/// and tracer.
public enum Benchmarks {
    /// Configuration of the Benchmarks library.
    public struct Configuration {
        /// Context of Benchmarks measures.
        /// The context properties will be added to metrics as tags.
        public struct Context {
            var applicationIdentifier: String
            var applicationName: String
            var applicationVersion: String
            var env: String
            var sdkVersion: String
            var deviceModel: String
            var osName: String
            var osVersion: String
            var run: String
            var scenario: String
            var branch: String

            public init(
                applicationIdentifier: String,
                applicationName: String,
                applicationVersion: String,
                env: String,
                sdkVersion: String,
                deviceModel: String,
                osName: String,
                osVersion: String,
                run: String,
                scenario: String,
                branch: String
            ) {
                self.applicationIdentifier = applicationIdentifier
                self.applicationName = applicationName
                self.applicationVersion = applicationVersion
                self.env = env
                self.sdkVersion = sdkVersion
                self.deviceModel = deviceModel
                self.osName = osName
                self.osVersion = osVersion
                self.run = run
                self.scenario = scenario
                self.branch = branch
            }
        }

        var clientToken: String
        var apiKey: String
        var context: Context

        public init(
            clientToken: String,
            apiKey: String,
            context: Context
        ) {
            self.clientToken = clientToken
            self.apiKey = apiKey
            self.context = context
        }
    }

    /// Configure an OpenTelemetry meter provider.
    ///
    /// - Parameter configuration: The Benchmark configuration.
    public static func meterProvider(with configuration: Configuration) -> MeterProvider {
        let metricExporter = MetricExporter(
            configuration: MetricExporter.Configuration(
                apiKey: configuration.apiKey,
                version: configuration.context.applicationVersion
            )
        )

        return MeterProviderBuilder()
            .with(pushInterval: 10)
            .with(processor: MetricProcessorSdk())
            .with(exporter: metricExporter)
            .with(resource: Resource(attributes: [
                "device_model": .string(configuration.context.deviceModel),
                "os": .string(configuration.context.osName),
                "os_version": .string(configuration.context.osVersion),
                "run": .string(configuration.context.run),
                "scenario": .string(configuration.context.scenario),
                "env": .string(configuration.context.env),
                "application_id": .string(configuration.context.applicationIdentifier),
                "sdk_version": .string(configuration.context.sdkVersion),
                "branch": .string(configuration.context.branch),
            ]))
            .build()
    }

    /// Configure an OpenTelemetry tracer provider.
    ///
    /// - Parameter configuration: The Benchmark configuration.
    public static func tracerProvider(with configuration: Configuration) -> TracerProvider {
        let exporterConfiguration = ExporterConfiguration(
            serviceName: configuration.context.applicationIdentifier,
            resource: "Benchmark Tracer",
            applicationName: configuration.context.applicationName,
            applicationVersion: configuration.context.applicationVersion,
            environment: "benchmarks",
            apiKey: configuration.apiKey,
            endpoint: .us1,
            uploadCondition: { true }
        )

        let exporter = try! DatadogExporter(config: exporterConfiguration)
        let processor = SimpleSpanProcessor(spanExporter: exporter)

        return TracerProviderBuilder()
            .add(spanProcessor: processor)
            .build()
    }
}
