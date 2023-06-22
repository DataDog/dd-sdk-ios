/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import DatadogRUM

/// Describes the configuration of all features.
///
/// It is build by resolving the raw `Datadog.Configuration` received from the user. As `Datadog.Configuration` contains
/// unvalidated and unresolved inputs, it should never be passed to features. Instead, `FeaturesConfiguration` should be used.
internal struct FeaturesConfiguration {
    struct Common {
        /// [Datadog Site](https://docs.datadoghq.com/getting_started/site/) for data uploads. It can be `nil` in V1
        /// if the SDK is configured using deprecated APIs: `set(logsEndpoint:)`, `set(tracesEndpoint:)` and `set(rumEndpoint:)`.
        let site: DatadogSite
        let clientToken: String
        let applicationName: String
        let applicationVersion: String
        let applicationBundleIdentifier: String
        let serviceName: String
        let environment: String
        let performance: PerformancePreset
        let source: String
        let variant: String?
        let origin: String?
        let sdkVersion: String
        let proxyConfiguration: [AnyHashable: Any]?
        let encryption: DataEncryption?
        let serverDateProvider: ServerDateProvider?
        let dateProvider: DateProvider
    }

    /// Configuration common to all features.
    let common: Common
    /// RUM feature configuration or `nil` if the feature is disabled.
    let rum: RUMConfiguration?
    /// Tracing feature enabled.
    let tracingEnabled: Bool
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
        var rum: RUMConfiguration?

        tracingEnabled = configuration.tracingEnabled

        let source = (configuration.additionalConfiguration[CrossPlatformAttributes.ddsource] as? String) ?? Datadog.Constants.ddsource
        let sdkVersion = (configuration.additionalConfiguration[CrossPlatformAttributes.sdkVersion] as? String) ?? __sdkVersion
        let appVersion = (configuration.additionalConfiguration[CrossPlatformAttributes.version] as? String) ?? appContext.bundleVersion ?? "0.0.0"
        let variant = configuration.additionalConfiguration[CrossPlatformAttributes.variant] as? String

        let debugOverride = appContext.processInfo.arguments.contains(LaunchArguments.Debug)
        if debugOverride {
            consolePrint("⚠️ Overriding sampling, verbosity, and upload frequency due to \(LaunchArguments.Debug) launch argument")
            Datadog.verbosityLevel = .debug
        }

        let dateProvider = SystemDateProvider()

        let common = Common(
            site: configuration.datadogEndpoint,
            clientToken: try ifValid(clientToken: configuration.clientToken),
            applicationName: appContext.bundleName ?? appContext.bundleType.rawValue,
            applicationVersion: appVersion,
            applicationBundleIdentifier: appContext.bundleIdentifier ?? "unknown",
            serviceName: configuration.serviceName ?? appContext.bundleIdentifier ?? "ios",
            environment: try ifValid(environment: configuration.environment),
            performance: PerformancePreset(
                batchSize: debugOverride ? .small : configuration.batchSize,
                uploadFrequency: debugOverride ? .frequent : configuration.uploadFrequency,
                bundleType: appContext.bundleType
            ),
            source: source,
            variant: variant,
            origin: CITestIntegration.active?.origin,
            sdkVersion: sdkVersion,
            proxyConfiguration: configuration.proxyConfiguration,
            encryption: configuration.encryption,
            serverDateProvider: configuration.serverDateProvider,
            dateProvider: dateProvider
        )

        if configuration.rumEnabled {
            let instrumentation = RUMConfiguration.Instrumentation(
                uiKitRUMViewsPredicate: configuration.rumUIKitViewsPredicate,
                uiKitRUMUserActionsPredicate: configuration.rumUIKitUserActionsPredicate,
                longTaskThreshold: configuration.rumLongTaskDurationThreshold
            )

            var configurationSampler = Sampler(samplingRate: 20)
            if let internalConfigurationSampleRate = configuration.additionalConfiguration[CrossPlatformAttributes.telemetryConfigurationSampleRate] as? Float {
                configurationSampler = Sampler(samplingRate: internalConfigurationSampleRate)
            }

            if let rumApplicationID = configuration.rumApplicationID {
                rum = RUMConfiguration(
                    applicationID: rumApplicationID,
                    sessionSampler: Sampler(samplingRate: debugOverride ? 100.0 : configuration.rumSessionsSamplingRate),
                    telemetrySampler: Sampler(samplingRate: configuration.rumTelemetrySamplingRate),
                    configurationTelemetrySampler: configurationSampler,
                    viewEventMapper: configuration.rumViewEventMapper,
                    resourceEventMapper: configuration.rumResourceEventMapper,
                    actionEventMapper: configuration.rumActionEventMapper,
                    errorEventMapper: configuration.rumErrorEventMapper,
                    longTaskEventMapper: configuration.rumLongTaskEventMapper,
                    instrumentation: instrumentation,
                    backgroundEventTrackingEnabled: configuration.rumBackgroundEventTrackingEnabled,
                    frustrationTrackingEnabled: configuration.rumFrustrationSignalsTrackingEnabled,
                    onSessionStart: configuration.rumSessionsListener,
                    firstPartyHosts: configuration.firstPartyHosts,
                    tracingSampler: Sampler(samplingRate: debugOverride ? 100.0 : configuration.tracingSamplingRate),
                    traceIDGenerator: DefaultTraceIDGenerator(),
                    rumAttributesProvider: configuration.rumResourceAttributesProvider,
                    vitalsFrequency: configuration.mobileVitalsFrequency.timeInterval,
                    dateProvider: dateProvider,
                    customIntakeURL: configuration.customRUMEndpoint,
                    testExecutionId: CITestIntegration.active?.testExecutionId
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

        // TODO: RUMM-2538 Update this wording with final V2 APIs
        if configuration.firstPartyHosts != nil && !configuration.tracingEnabled && !configuration.rumEnabled {
            let error = ProgrammerError(
                description: """
                To use `.trackURLSession(firstPartyHosts:)` either RUM or Tracing must be enabled.
                Use: `.enableTracing(true)` or `.enableRUM(true)`.
                """
            )
            consolePrint("\(error)")
        }

        if configuration.rumResourceAttributesProvider != nil && configuration.firstPartyHosts == nil {
            let error = ProgrammerError(
                description: """
                To use `.setRUMResourceAttributesProvider(_:)` URLSession tracking must be enabled
                with `.trackURLSession(firstPartyHosts:)`.
                """
            )
            consolePrint("\(error)")
        }

        self.common = common
        self.rum = rum
    }
}

extension Datadog.Configuration.VitalsFrequency {
    var timeInterval: TimeInterval? {
        switch self {
        case .frequent: return 0.1
        case .average: return 0.5
        case .rare: return 1
        case .never: return nil
        }
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
