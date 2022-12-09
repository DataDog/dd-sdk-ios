/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Datadog site that SDK sends data to.
/// See: https://docs.datadoghq.com/getting_started/site/
public typealias DatadogSite = Datadog.Configuration.DatadogEndpoint

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

    /// The name of the service that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let service: String

    /// The name of the environment that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let env: String

    /// The version of the application that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    let version: String

    /// Denotes the mobile application's platform, such as `"ios"` or `"flutter"` that data is generated from.
    ///  - See: Datadog [Reserved Attributes](https://docs.datadoghq.com/logs/log_configuration/attributes_naming_convention/#reserved-attributes).
    let source: String

    /// The variant of the build, equivelent to Android's "Flavor".  Only used by cross platform SDKs
    let variant: String?

    /// The version of Datadog iOS SDK.
    let sdkVersion: String

    // MARK: - Application Specific

    /// Current device information.
    let device: DeviceInfo

    // MARK: Providers

    /// NTP time correction provider.
    let dateCorrector: DateCorrector

    /// Network information provider.
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType

    /// Carrier information provider.
    let carrierInfoProvider: CarrierInfoProviderType

    /// User information provider.
    let userInfoProvider: UserInfoProvider
}
