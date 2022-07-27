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
    // MARK: Datadog Specific

    /// [Datadog Site](https://docs.datadoghq.com/getting_started/site/) for data uploads. It can be `nil` in V1
    /// if the SDK is configured using deprecated APIs: `set(logsEndpoint:)`, `set(tracesEndpoint:)` and `set(rumEndpoint:)`.
    let site: DatadogSite?

    /// The client token allowing for data uploads to [Datadog Site](https://docs.datadoghq.com/getting_started/site/).
    let clientToken: String

    /// The name of the service that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let service: String

    /// The name of the environment that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let env: String

    /// The version of the application that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let version: String

    /// Denotes the mobile application's platform, such as `"ios"` or `"flutter"` that data is generated from.
    ///  - See: Datadog [Reserved Attributes](https://docs.datadoghq.com/logs/log_configuration/attributes_naming_convention/#reserved-attributes).
    let source: String

    /// The version of Datadog iOS SDK.
    let sdkVersion: String

    /// The name of [CI Visibility](https://docs.datadoghq.com/continuous_integration/) origin.
    /// It is only set if the SDK is running with a context passed from [Swift Tests](https://docs.datadoghq.com/continuous_integration/setup_tests/swift/?tab=swiftpackagemanager) library.
    let ciAppOrigin: String?

    // MARK: - Application Specific

    /// The name of the application, read from `Info.plist` (`CFBundleExecutable`).
    let applicationName: String

    /// The bundle identifier, read from `Info.plist` (`CFBundleIdentifier`).
    let applicationBundleIdentifier: String

    /// Date of SDK initialization measured in device time (without NTP correction).
    let sdkInitDate: Date

    /// Current device information.
    let device: DeviceInfo

    // MARK: Providers

    /// Time provider.
    let dateProvider: DateProvider

    /// NTP time correction provider.
    let dateCorrector: DateCorrector

    /// Network information provider.
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType

    /// Carrier information provider.
    let carrierInfoProvider: CarrierInfoProviderType

    /// User information provider.
    let userInfoProvider: UserInfoProvider

    /// Provides the history of app foreground / background states and lets subscribe for their updates.
    let appStateListener: AppStateListening

    /// Provides the information about application launch time.
    let launchTimeProvider: LaunchTimeProviderType
}
