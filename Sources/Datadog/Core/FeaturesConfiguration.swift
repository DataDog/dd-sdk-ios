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
        let origin: String?
        let sdkVersion: String
        let proxyConfiguration: [AnyHashable: Any]?
        let encryption: DataEncryption?
    }

    struct Logging {
        let common: Common
        let uploadURL: URL
        let clientToken: String
        let logEventMapper: LogEventMapper?
    }

    struct Tracing {
        let common: Common
        let uploadURL: URL
        let clientToken: String
        let spanEventMapper: SpanEventMapper?
    }

    struct RUM {
        struct Instrumentation {
            let uiKitRUMViewsPredicate: UIKitRUMViewsPredicate?
            let uiKitRUMUserActionsPredicate: UIKitRUMUserActionsPredicate?
            let longTaskThreshold: TimeInterval?
        }

        let common: Common
        let uploadURL: URL
        let clientToken: String
        let applicationID: String
        let sessionSampler: Sampler
        let uuidGenerator: RUMUUIDGenerator
        let viewEventMapper: RUMViewEventMapper?
        let resourceEventMapper: RUMResourceEventMapper?
        let actionEventMapper: RUMActionEventMapper?
        let errorEventMapper: RUMErrorEventMapper?
        let longTaskEventMapper: RUMLongTaskEventMapper?
        /// RUM auto instrumentation configuration, `nil` if not enabled.
        let instrumentation: Instrumentation?
        let backgroundEventTrackingEnabled: Bool
        let onSessionStart: RUMSessionListener?
    }

    struct URLSessionAutoInstrumentation {
        /// First party hosts defined by the user.
        let userDefinedFirstPartyHosts: Set<String>
        /// URLs used internally by the SDK - they are not instrumented.
        let sdkInternalURLs: Set<String>
        /// An optional RUM Resource attributes provider.
        let rumAttributesProvider: URLSessionRUMAttributesProvider?

        /// If the Tracing instrumentation should be enabled.
        let instrumentTracing: Bool
        /// If the RUM instrumentation should be enabled.
        let instrumentRUM: Bool
    }

    struct CrashReporting {
        /// The `DDCrashReportingPluginType` implementation provided by `DatadogCrashReporting` library.
        let crashReportingPlugin: DDCrashReportingPluginType
    }

    struct InternalMonitoring {
        let common: Common
        let sdkServiceName: String
        let sdkEnvironment: String
        /// Internal monitoring logger's name.
        let loggerName = "im-logger"
        let logsUploadURL: URL
        /// The client token authorized for monitoring org (likely it's different than client token for other features).
        let clientToken: String
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
    /// Crash Reporting feature configuration or `nil` if the feature was not enabled.
    let crashReporting: CrashReporting?
    /// Internal Monitoring feature configuration or `nil` if the feature was not enabled.
    let internalMonitoring: InternalMonitoring?
}

extension FeaturesConfiguration {
    /// Builds and validates the configuration for all features.
    ///
    /// It takes two types received from the user: `Datadog.Configuration` and `AppContext` and blends them together
    /// with resolving defaults and ensuring the configuration consistency.
    ///
    /// Throws an error on invalid user input, i.e. broken custom URL.
    /// Prints a warning if configuration is inconsistent, i.e. RUM is enabled, but RUM Application ID was not specified.
    init(configuration: Datadog.Configuration, appContext: AppContext, hostsSanitizer: HostsSanitizing = HostsSanitizer()) throws {
        var logging: Logging?
        var tracing: Tracing?
        var rum: RUM?
        var urlSessionAutoInstrumentation: URLSessionAutoInstrumentation?
        var crashReporting: CrashReporting?
        var internalMonitoring: InternalMonitoring?

        var logsEndpoint = configuration.logsEndpoint
        var tracesEndpoint = configuration.tracesEndpoint
        var rumEndpoint = configuration.rumEndpoint

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

        let source = (configuration.additionalConfiguration[CrossPlatformAttributes.ddsource] as? String) ?? Datadog.Constants.ddsource
        let sdkVersion = (configuration.additionalConfiguration[CrossPlatformAttributes.sdkVersion] as? String) ?? __sdkVersion

        let debugOverride = appContext.processInfo.arguments.contains(Datadog.LaunchArguments.Debug)
        if debugOverride {
            consolePrint("⚠️ Overriding sampling, verbosity, and upload frequency due to \(Datadog.LaunchArguments.Debug) launch argument")
            Datadog.verbosityLevel = .debug
        }

        let common = Common(
            applicationName: appContext.bundleName ?? appContext.bundleType.rawValue,
            applicationVersion: appContext.bundleVersion ?? "0.0.0",
            applicationBundleIdentifier: appContext.bundleIdentifier ?? "unknown",
            serviceName: configuration.serviceName ?? appContext.bundleIdentifier ?? "ios",
            environment: try ifValid(environment: configuration.environment),
            performance: PerformancePreset(
                batchSize: debugOverride ? .small : configuration.batchSize,
                uploadFrequency: debugOverride ? .frequent : configuration.uploadFrequency,
                bundleType: appContext.bundleType
            ),
            source: source,
            origin: CITestIntegration.active?.origin,
            sdkVersion: sdkVersion,
            proxyConfiguration: configuration.proxyConfiguration,
            encryption: configuration.encryption
        )

        if configuration.loggingEnabled {
            logging = Logging(
                common: common,
                uploadURL: try ifValid(endpointURLString: logsEndpoint.url),
                clientToken: try ifValid(clientToken: configuration.clientToken),
                logEventMapper: configuration.logEventMapper
            )
        }

        if configuration.tracingEnabled {
            tracing = Tracing(
                common: common,
                uploadURL: try ifValid(endpointURLString: tracesEndpoint.url),
                clientToken: try ifValid(clientToken: configuration.clientToken),
                spanEventMapper: configuration.spanEventMapper
            )
        }

        if configuration.rumEnabled {
            let instrumentation = RUM.Instrumentation(
                uiKitRUMViewsPredicate: configuration.rumUIKitViewsPredicate,
                uiKitRUMUserActionsPredicate: configuration.rumUIKitUserActionsPredicate,
                longTaskThreshold: configuration.rumLongTaskDurationThreshold
            )

            if let rumApplicationID = configuration.rumApplicationID {
                rum = RUM(
                    common: common,
                    uploadURL: try ifValid(endpointURLString: rumEndpoint.url),
                    clientToken: try ifValid(clientToken: configuration.clientToken),
                    applicationID: rumApplicationID,
                    sessionSampler: Sampler(samplingRate: debugOverride ? 100.0 : configuration.rumSessionsSamplingRate),
                    uuidGenerator: DefaultRUMUUIDGenerator(),
                    viewEventMapper: configuration.rumViewEventMapper,
                    resourceEventMapper: configuration.rumResourceEventMapper,
                    actionEventMapper: configuration.rumActionEventMapper,
                    errorEventMapper: configuration.rumErrorEventMapper,
                    longTaskEventMapper: configuration.rumLongTaskEventMapper,
                    instrumentation: instrumentation,
                    backgroundEventTrackingEnabled: configuration.rumBackgroundEventTrackingEnabled,
                    onSessionStart: configuration.rumSessionsListener
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
                    userDefinedFirstPartyHosts: hostsSanitizer.sanitized(
                        hosts: firstPartyHosts,
                        warningMessage: "The first party host configured for Datadog SDK is not valid"
                    ),
                    sdkInternalURLs: [
                        logsEndpoint.url,
                        tracesEndpoint.url,
                        rumEndpoint.url
                    ],
                    rumAttributesProvider: configuration.rumResourceAttributesProvider,
                    instrumentTracing: configuration.tracingEnabled,
                    instrumentRUM: configuration.rumEnabled
                )
            } else {
                let error = ProgrammerError(
                    description: """
                    To use `.trackURLSession(firstPartyHosts:)` either RUM or Tracing must be enabled.
                    Use: `.enableTracing(true)` or `.enableRUM(true)`.
                    """
                )
                consolePrint("\(error)")
            }
        } else if configuration.rumResourceAttributesProvider != nil {
            let error = ProgrammerError(
                description: """
                To use `.setRUMResourceAttributesProvider(_:)` URLSession tracking must be enabled
                with `.trackURLSession(firstPartyHosts:)`.
                """
            )
            consolePrint("\(error)")
        }

        if let crashReportingPlugin = configuration.crashReportingPlugin {
            if configuration.loggingEnabled || configuration.rumEnabled {
                crashReporting = CrashReporting(crashReportingPlugin: crashReportingPlugin)
            } else {
                let error = ProgrammerError(
                    description: """
                    To use `.enableCrashReporting(using:)` either RUM or Logging must be enabled.
                    Use: `.enableLogging(true)` or `.enableRUM(true)`.
                    """
                )
                consolePrint("\(error)")
            }
        }

        if let internalMonitoringClientToken = configuration.internalMonitoringClientToken {
            internalMonitoring = InternalMonitoring(
                common: common,
                sdkServiceName: "dd-sdk-ios",
                sdkEnvironment: "prod",
                logsUploadURL: try ifValid(endpointURLString: Datadog.Configuration.DatadogEndpoint.us1.logsEndpoint.url),
                clientToken: try ifValid(clientToken: internalMonitoringClientToken)
            )
        }

        self.common = common
        self.logging = logging
        self.tracing = tracing
        self.rum = rum
        self.urlSessionAutoInstrumentation = urlSessionAutoInstrumentation
        self.crashReporting = crashReporting
        self.internalMonitoring = internalMonitoring
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

private func ifValid(endpointURLString: String) throws -> URL {
    guard let endpointURL = URL(string: endpointURLString) else {
        throw ProgrammerError(description: "The `url` in `.custom(url:)` must be a valid URL string.")
    }
    return endpointURL
}

private func ifValid(clientToken: String) throws -> String {
    if clientToken.isEmpty {
        throw ProgrammerError(description: "`clientToken` cannot be empty.")
    }
    return clientToken
}
