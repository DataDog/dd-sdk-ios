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
        let source: String
    }

    struct Logging {
        let common: Common
        let uploadURLWithClientToken: URL
    }

    struct Tracing {
        let common: Common
        let uploadURLWithClientToken: URL
    }

    struct RUM {
        struct AutoInstrumentation {
            let uiKitRUMViewsPredicate: UIKitRUMViewsPredicate?
            let uiKitActionsTrackingEnabled: Bool
        }

        let common: Common
        let uploadURLWithClientToken: URL
        let applicationID: String
        let sessionSamplingRate: Float
        let eventMapper: RUMEventsMapper
        /// RUM auto instrumentation configuration, `nil` if not enabled.
        let autoInstrumentation: AutoInstrumentation?
    }

    struct URLSessionAutoInstrumentation {
        /// First party hosts defined by the user.
        let userDefinedFirstPartyHosts: Set<String>
        /// URLs used internally by the SDK - they are not instrumented.
        let sdkInternalURLs: Set<String>

        /// If the Tracing instrumentation should be enabled.
        let instrumentTracing: Bool
        /// If the RUM instrumentation should be enabled.
        let instrumentRUM: Bool
    }

    /// Configuration common to all features.
    let common: Common
    /// Logging feature configuration or `nil` if the feature is disabled.
    let logging: Logging?
    /// Tracing feature configuration or `nil` if the feature is disabled.
    let tracing: Tracing?
    /// RUM feature configuration or `nil` if the feature is disabled.
    let rum: RUM?
    /// `URLSession` auto instrumentation configuration, `nil` if not enabled.
    let urlSessionAutoInstrumentation: URLSessionAutoInstrumentation?
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
        var urlSessionAutoInstrumentation: URLSessionAutoInstrumentation?

        var logsEndpoint = configuration.logsEndpoint
        var tracesEndpoint = configuration.tracesEndpoint
        var rumEndpoint = configuration.rumEndpoint

        let source = (configuration.additionalConfiguration["_dd.source"] as? String) ?? Datadog.Constants.ddsource

        if let datadogEndpoint = configuration.datadogEndpoint {
            // If `.set(endpoint:)` API was used, it should override the values
            // set by deprecated `.set(<feature>Endpoint:)` APIs.
            logsEndpoint = datadogEndpoint.logsEndpoint
            tracesEndpoint = datadogEndpoint.tracesEndpoint
            rumEndpoint = datadogEndpoint.rumEndpoint
        }

        if let customLogsEndpoint = configuration.customLogsEndpoint {
            // If `.set(cusstomLogsEndpoint:)` API was used, it should override logs endpoint
            logsEndpoint = .custom(url: customLogsEndpoint.absoluteString)
        }

        if let customTracesEndpoint = configuration.customTracesEndpoint {
            // If `.set(cusstomLogsEndpoint:)` API was used, it should override traces endpoint
            tracesEndpoint = .custom(url: customTracesEndpoint.absoluteString)
        }

        if let customRUMEndpoint = configuration.customRUMEndpoint {
            // If `.set(cusstomLogsEndpoint:)` API was used, it should override RUM endpoint
            rumEndpoint = .custom(url: customRUMEndpoint.absoluteString)
        }

        let common = Common(
            applicationName: appContext.bundleName ?? appContext.bundleType.rawValue,
            applicationVersion: appContext.bundleVersion ?? "0.0.0",
            applicationBundleIdentifier: appContext.bundleIdentifier ?? "unknown",
            serviceName: configuration.serviceName ?? appContext.bundleIdentifier ?? "ios",
            environment: try ifValid(environment: configuration.environment),
            performance: PerformancePreset(
                batchSize: configuration.batchSize,
                uploadFrequency: configuration.uploadFrequency,
                bundleType: appContext.bundleType
            ),
            source: source
        )

        if configuration.loggingEnabled {
            logging = Logging(
                common: common,
                uploadURLWithClientToken: try ifValid(
                    endpointURLString: logsEndpoint.url,
                    clientToken: configuration.clientToken
                )
            )
        }

        if configuration.tracingEnabled {
            tracing = Tracing(
                common: common,
                uploadURLWithClientToken: try ifValid(
                    endpointURLString: tracesEndpoint.url,
                    clientToken: configuration.clientToken
                )
            )
        }

        if configuration.rumEnabled {
            var autoInstrumentation: RUM.AutoInstrumentation?

            if configuration.rumUIKitViewsPredicate != nil || configuration.rumUIKitActionsTrackingEnabled {
                autoInstrumentation = RUM.AutoInstrumentation(
                    uiKitRUMViewsPredicate: configuration.rumUIKitViewsPredicate,
                    uiKitActionsTrackingEnabled: configuration.rumUIKitActionsTrackingEnabled
                )
            }

            if let rumApplicationID = configuration.rumApplicationID {
                rum = RUM(
                    common: common,
                    uploadURLWithClientToken: try ifValid(
                        endpointURLString: rumEndpoint.url,
                        clientToken: configuration.clientToken
                    ),
                    applicationID: rumApplicationID,
                    sessionSamplingRate: configuration.rumSessionsSamplingRate,
                    eventMapper: RUMEventsMapper(
                        viewEventMapper: configuration.rumViewEventMapper,
                        errorEventMapper: configuration.rumErrorEventMapper,
                        resourceEventMapper: configuration.rumResourceEventMapper,
                        actionEventMapper: configuration.rumActionEventMapper
                    ),
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

        if let firstPartyHosts = configuration.firstPartyHosts {
            if configuration.tracingEnabled || configuration.rumEnabled {
                urlSessionAutoInstrumentation = URLSessionAutoInstrumentation(
                    userDefinedFirstPartyHosts: sanitized(firstPartyHosts: firstPartyHosts),
                    sdkInternalURLs: [
                        logsEndpoint.url,
                        tracesEndpoint.url,
                        rumEndpoint.url
                    ],
                    instrumentTracing: configuration.tracingEnabled,
                    instrumentRUM: configuration.rumEnabled
                )
            } else {
                let error = ProgrammerError(
                    description: """
                    To use `.trackURLSession(firstPartyHosts:)` either RUM or Tracing should be enabled.
                    """
                )
                consolePrint("\(error)")
            }
        }

        self.common = common
        self.logging = logging
        self.tracing = tracing
        self.rum = rum
        self.urlSessionAutoInstrumentation = urlSessionAutoInstrumentation
    }
}

private func ifValid(environment: String) throws -> String {
    /// 1. cannot be more than 200 chars (including `env:` prefix)
    /// 2. cannot end with `:`
    /// 3. can contain letters, numbers and _:./-_ (other chars are converted to _ at backend)
    let regex = #"^[a-zA-Z0-9_:./-]{0,195}[a-zA-Z0-9_./-]$"#
    if environment.range(of: regex, options: .regularExpression, range: nil, locale: nil) == nil {
        throw ProgrammerError(description: "`environment`: \(environment) contains illegal characters (only alphanumerics and `_` are allowed)")
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

private func sanitized(firstPartyHosts: Set<String>) -> Set<String> {
    let urlRegex = #"^(http|https)://(.*)"#
    let hostRegex = #"^(([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])\.)+([A-Za-z]|[A-Za-z][A-Za-z0-9-]*[A-Za-z0-9])$"#
    let ipRegex = #"^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$"#

    var warnings: [String] = []

    let array: [String] = firstPartyHosts.compactMap { host in
        if host.range(of: urlRegex, options: .regularExpression) != nil {
            // if an URL is given instead of the host, take its `host` part
            if let sanitizedHost = URL(string: host)?.host {
                warnings.append("'\(host)' is an url and will be sanitized to: '\(sanitizedHost)'.")
                return sanitizedHost
            } else {
                warnings.append("'\(host)' is not a valid host name and will be dropped.")
                return nil
            }
        } else if host.range(of: hostRegex, options: .regularExpression) != nil {
            // if a valid host name is given, accept it
            return host
        } else if host.range(of: ipRegex, options: .regularExpression) != nil {
            // if a valid IP address is given, accept it
            return host
        } else if host == "localhost" {
            // if "localhost" given, accept it
            return host
        } else {
            // otherwise, drop
            warnings.append("'\(host)' is not a valid host name and will be dropped.")
            return nil
        }
    }

    warnings.forEach { warning in
        consolePrint(
            """
            ⚠️ The first party host configured for Datadog SDK is not valid: \(warning)
            """
        )
    }

    return Set(array)
}
