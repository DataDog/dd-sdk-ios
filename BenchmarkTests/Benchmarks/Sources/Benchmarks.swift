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

let instrumentationName = "benchmarks"
let instrumentationVersion = "1.0.0"

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
    
    /// Configure OpenTelemetry metrics meter and start measuring Memory.
    ///
    /// - Parameter configuration: The Benchmark configuration.
    public static func enableMetrics(with configuration: Configuration) {
        let metricExporter = MetricExporter(
            configuration: MetricExporter.Configuration(
                apiKey: configuration.apiKey,
                version: instrumentationVersion
            )
        )

        let meterProvider = MeterProviderBuilder()
            .with(pushInterval: 10)
            .with(processor: MetricProcessorSdk())
            .with(exporter: metricExporter)
            .with(resource: Resource())
            .build()

        let meter = meterProvider.get(
            instrumentationName: instrumentationName,
            instrumentationVersion: instrumentationVersion
        )

        let labels = [
            "device_model": configuration.context.deviceModel,
            "os": configuration.context.osName,
            "os_version": configuration.context.osVersion,
            "run": configuration.context.run,
            "scenario": configuration.context.scenario,
            "application_id": configuration.context.applicationIdentifier,
            "sdk_version": configuration.context.sdkVersion,
            "branch": configuration.context.branch,
        ]

        let queue = DispatchQueue(label: "com.datadoghq.benchmarks.metrics", qos: .utility)

        let memory = Memory(queue: queue)
        _ = meter.createDoubleObservableGauge(name: "ios.benchmark.memory") { metric in
            // report the maximum memory footprint that was recorded during push interval
            if let value = memory.aggregation?.max {
                metric.observe(value: value, labels: labels)
            }

            memory.reset()
        }

        let cpu = CPU(queue: queue)
        _ = meter.createDoubleObservableGauge(name: "ios.benchmark.cpu") { metric in
            // report the average cpu usage that was recorded during push interval
            if let value = cpu.aggregation?.avg {
                metric.observe(value: value, labels: labels)
            }

            cpu.reset()
        }

        let fps = FPS()
        _ = meter.createIntObservableGauge(name: "ios.benchmark.fps.min") { metric in
            // report the minimum frame rate that was recorded during push interval
            if let value = fps.aggregation?.min {
                metric.observe(value: value, labels: labels)
            }

            fps.reset()
        }

        OpenTelemetry.registerMeterProvider(meterProvider: meterProvider)
    }

    /// Configure and register a OpenTelemetry Tracer.
    ///
    /// - Parameter configuration: The Benchmark configuration.
    public static func enableTracer(with configuration: Configuration) {
        let exporterConfiguration = ExporterConfiguration(
            serviceName: configuration.context.applicationIdentifier,
            resource: "Benchmark Tracer",
            applicationName: configuration.context.applicationName,
            applicationVersion: configuration.context.applicationVersion,
            environment: "benchmarks",
            apiKey: configuration.apiKey,
            endpoint: .us1,
            uploadCondition: { true },
            performancePreset: .instantDataDelivery
        )
        
        let exporter = try! DatadogExporter(config: exporterConfiguration)
        let processor = SimpleSpanProcessor(spanExporter: exporter)

        let provider = TracerProviderBuilder()
            .with(resource: Resource(attributes: [
                "device_model": configuration.context.deviceModel,
                "os": configuration.context.osName,
                "os_version": configuration.context.osVersion,
                "run": configuration.context.run,
                "scenario": configuration.context.scenario,
                "sdk_version": configuration.context.sdkVersion,
                "branch": configuration.context.branch,
            ].mapValues { .string($0) }))
            .add(spanProcessor: processor)
            .with(sampler: Samplers.traceIdRatio(ratio: 0.01))
            .build()

        OpenTelemetry.registerTracerProvider(tracerProvider: provider)
    }
}
