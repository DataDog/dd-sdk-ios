/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Datadog site that SDK sends data to.
/// See: https://docs.datadoghq.com/getting_started/site/
internal typealias DatadogSite = Datadog.Configuration.DatadogEndpoint

/// The SDK context for V1, until the V2 context is created.
///
/// V2-like context can be safely assembled from V1 core components. Unlike in V2, this requires more hassle and is less performant:
/// - different values for V1 context need to be read either from common configuration or through shared dependencies (providers);
/// - V1 context is not asynchronous, and some providers block their threads for getting their value.
///
/// `DatadogV1Context` can be safely captured during component initialization. It will never change during component's lifespan, meaning that:
/// - exposed static configuration won't change;
/// - bundled provider references won't change (although the value they provide will be different over time).
internal struct DatadogV1Context {
    private let configuration: CoreConfiguration
    private let dependencies: CoreDependencies
    private let appVersionProvider: AppVersionProvider

    init(configuration: CoreConfiguration, dependencies: CoreDependencies, appVersionProvider: AppVersionProvider) {
        self.configuration = configuration
        self.dependencies = dependencies
        self.appVersionProvider = appVersionProvider
    }
}

// MARK: - Configuration

/// This extension bundles different parts of the SDK core configuration.
internal extension DatadogV1Context {
    // MARK: - Datadog Specific

    /// [Datadog Site](https://docs.datadoghq.com/getting_started/site/) for data uploads. It can be `nil` in V1
    /// if the SDK is configured using deprecated APIs: `set(logsEndpoint:)`, `set(tracesEndpoint:)` and `set(rumEndpoint:)`.
    var site: DatadogSite? { configuration.site }

    /// The client token allowing for data uploads to [Datadog Site](https://docs.datadoghq.com/getting_started/site/).
    var clientToken: String { configuration.clientToken }

    /// The name of the service that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    var service: String { configuration.serviceName }

    /// The name of the environment that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    var env: String { configuration.environment }

    /// The version of the application that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    var version: String { appVersionProvider.value }

    /// Denotes the mobile application's platform, such as `"ios"` or `"flutter"` that data is generated from.
    ///  - See: Datadog [Reserved Attributes](https://docs.datadoghq.com/logs/log_configuration/attributes_naming_convention/#reserved-attributes).
    var source: String { configuration.source }

    /// The variant of the build, equivelent to Android's "Flavor".  Only used by cross platform SDKs
    var variant: String? { configuration.variant }

    /// The version of Datadog iOS SDK.
    var sdkVersion: String { configuration.sdkVersion }

    /// The name of [CI Visibility](https://docs.datadoghq.com/continuous_integration/) origin.
    /// It is only set if the SDK is running with a context passed from [Swift Tests](https://docs.datadoghq.com/continuous_integration/setup_tests/swift/?tab=swiftpackagemanager) library.
    var ciAppOrigin: String? { configuration.origin }

    // MARK: - Application Specific

    /// The name of the application, read from `Info.plist` (`CFBundleExecutable`).
    var applicationName: String { configuration.applicationName }

    /// The bundle identifier, read from `Info.plist` (`CFBundleIdentifier`).
    var applicationBundleIdentifier: String { configuration.applicationBundleIdentifier }

    /// Date of SDK initialization measured in device time (without NTP correction).
    var sdkInitDate: Date { dependencies.sdkInitDate }

    /// Current device information.
    var device: DeviceInfo { dependencies.deviceInfo }
}

// MARK: - Providers

/// This extension bundles different providers managed by the SDK core.
internal extension DatadogV1Context {
    /// Time provider.
    var dateProvider: DateProvider { dependencies.dateProvider }

    /// NTP time correction provider.
    var dateCorrector: DateCorrector { dependencies.dateCorrector }

    /// Network information provider.
    var networkConnectionInfoProvider: NetworkConnectionInfoProviderType { dependencies.networkConnectionInfoProvider }

    /// Carrier information provider.
    var carrierInfoProvider: CarrierInfoProviderType { dependencies.carrierInfoProvider }

    /// User information provider.
    var userInfoProvider: UserInfoProvider { dependencies.userInfoProvider }

    /// Provides the history of app foreground / background states and lets subscribe for their updates.
    var appStateListener: AppStateListening { dependencies.appStateListener }

    /// Provides the information about application launch time.
    var launchTimeProvider: LaunchTimeProviderType { dependencies.launchTimeProvider }
}
