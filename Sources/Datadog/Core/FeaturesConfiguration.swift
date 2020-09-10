/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Describes the configuration of all features.
///
/// It is build by resolving the raw `Datadog.Configuration` received from the user. As `Datadog.Configuration` contains
/// unvalidated and unresolved inputs, it should never be passed to features. Instead, `FeaturesConfiguration` should be used.
internal struct FeaturesConfiguration {
    struct Common {
        let applicationName: String
        let applicationVersion: String
        let applicationBundleIdentifier: String
        let serviceName: String
        let environment: String
        let performance: PerformancePreset
    }

    struct Logging {
        let common: Common
        let uploadURLWithClientToken: URL
    }

    struct Tracing {
        struct AutoInstrumentation {
            let tracedHosts: Set<String>
            let excludedHosts: Set<String>
        }

        let common: Common
        let uploadURLWithClientToken: URL
        /// Tracing auto instrumentation configuration, `nil` if not enabled.
        let autoInstrumentation: AutoInstrumentation?
    }

    struct RUM {
        struct AutoInstrumentation {
            // TODO: RUMM-713 Add RUM Views insturmentation configuration
            // TODO: RUMM-717 Add RUM Actions insturmentation configuration
            // TODO: RUMM-718 Add RUM Resources insturmentation configuration
        }

        let common: Common
        let uploadURLWithClientToken: URL
        let applicationID: String
        let sessionSamplingRate: Float
        /// RUM auto instrumentation configuration, `nil` if not enabled.
        let autoInstrumentation: AutoInstrumentation?
    }

    /// Configuration common to all features.
    let common: Common
    /// Logging feature configuration or `nil` if the feature is disabled.
    let logging: Logging?
    /// Tracing feature configuration or `nil` if the feature is disabled.
    let tracing: Tracing?
    /// RUM feature configuration or `nil` if the feature is disabled.
    let rum: RUM?
}

extension FeaturesConfiguration {
    /// Builds and validates the configuration for all features.
    ///
    /// It takes two types received from the user: `Datadog.Configuration` and `AppContext` and blends them together
    /// with resolving defaults and ensuring the configuration consistency.
    ///
    /// Throws an error on invalid user input, i.e. broken custom URL.
    /// Prints a warning if configuration is inconsistent, i.e. RUM is enabled, but RUM Application ID was not specified.
    init(configuration: Datadog.Configuration, appContext: AppContext) throws {
        var logging: Logging?
        var tracing: Tracing?
        var rum: RUM?

        let common = Common(
            applicationName: appContext.bundleName ?? appContext.bundleType.rawValue,
            applicationVersion: appContext.bundleVersion ?? "0.0.0",
            applicationBundleIdentifier: appContext.bundleIdentifier ?? "unknown",
            serviceName: configuration.serviceName ?? appContext.bundleIdentifier ?? "ios",
            environment: try ifValid(environment: configuration.environment),
            performance: .best(for: appContext.bundleType)
        )

        if configuration.loggingEnabled {
            logging = Logging(
                common: common,
                uploadURLWithClientToken: try ifValid(
                    endpointURLString: configuration.logsEndpoint.url,
                    clientToken: configuration.clientToken
                )
            )
        }

        if configuration.tracingEnabled {
            var autoInstrumentation: Tracing.AutoInstrumentation?

            if !configuration.tracedHosts.isEmpty {
                autoInstrumentation = Tracing.AutoInstrumentation(
                    tracedHosts: configuration.tracedHosts,
                    excludedHosts: [
                        configuration.logsEndpoint.url,
                        configuration.tracesEndpoint.url,
                        configuration.rumEndpoint.url
                    ]
                )
            }

            tracing = Tracing(
                common: common,
                uploadURLWithClientToken: try ifValid(
                    endpointURLString: configuration.tracesEndpoint.url,
                    clientToken: configuration.clientToken
                ),
                autoInstrumentation: autoInstrumentation
            )
        }

        if configuration.rumEnabled {
            // TODO: RUMM-713 RUMM-717 RUMM-718 Enable RUM.AutoInstrumentation conditionally
            let autoInstrumentation: RUM.AutoInstrumentation? = nil

            if let rumApplicationID = configuration.rumApplicationID {
                rum = RUM(
                    common: common,
                    uploadURLWithClientToken: try ifValid(
                        endpointURLString: configuration.rumEndpoint.url,
                        clientToken: configuration.clientToken
                    ),
                    applicationID: rumApplicationID,
                    sessionSamplingRate: configuration.rumSessionsSamplingRate,
                    autoInstrumentation: autoInstrumentation
                )
            } else {
                let error = ProgrammerError(
                    description: """
                    In order to use the RUM feature, `Datadog.Configuration` must be constructed using:
                    `.builderUsing(rumApplicationID:rumClientToken:environment:)`
                    """
                )
                consolePrint("\(error)")
            }
        }

        self.common = common
        self.logging = logging
        self.tracing = tracing
        self.rum = rum
    }
}

private func ifValid(environment: String) throws -> String {
    let regex = #"^[a-zA-Z0-9_]+$"#
    if environment.range(of: regex, options: .regularExpression, range: nil, locale: nil) == nil {
        throw ProgrammerError(description: "`environment` contains illegal characters (only alphanumerics and `_` are allowed)")
    }
    return environment
}

private func ifValid(endpointURLString: String, clientToken: String) throws -> URL {
    guard let endpointURL = URL(string: endpointURLString) else {
        throw ProgrammerError(description: "The `url` in `.custom(url:)` must be a valid URL string.")
    }
    if clientToken.isEmpty {
        throw ProgrammerError(description: "`clientToken` cannot be empty.")
    }
    let endpointURLWithClientToken = endpointURL.appendingPathComponent(clientToken)
    guard let url = URL(string: endpointURLWithClientToken.absoluteString) else {
        throw ProgrammerError(description: "Cannot build upload URL.")
    }
    return url
}
