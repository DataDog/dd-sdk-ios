/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Benchmark entrypoint to configure metrics collection.
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

    /// Configure a meter provider.
    ///
    /// - Parameter configuration: The Benchmark configuration.
    public static func meterProvider(with configuration: Configuration) -> MeterProvider {
        let metricExporter = MetricExporter(
            configuration: MetricExporter.Configuration(
                apiKey: configuration.apiKey,
                version: configuration.context.applicationVersion
            )
        )

        let resource: [String: String] = [
            "device_model": configuration.context.deviceModel,
            "os": configuration.context.osName,
            "os_version": configuration.context.osVersion,
            "run": configuration.context.run,
            "scenario": configuration.context.scenario,
            "env": configuration.context.env,
            "application_id": configuration.context.applicationIdentifier,
            "sdk_version": configuration.context.sdkVersion,
            "branch": configuration.context.branch,
        ]

        return MeterProvider(
            exporter: metricExporter,
            pushInterval: 10,
            resource: resource
        )
    }
}
