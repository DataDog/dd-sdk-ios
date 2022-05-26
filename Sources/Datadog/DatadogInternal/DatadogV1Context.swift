/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// The SDK context for V1, until the V2 context is created.
///
/// V2-like context can be safely assembled from V1 core components. Unlike in V2, this requires more hassle and is less performant:
/// - different values for V1 context need to be read either from common configuration or through shared dependencies (providers);
/// - V1 context is not asynchronous, and some providers block their threads for getting their value.
///
internal struct DatadogV1Context {
    private let configuration: CoreConfiguration
    private let dependencies: CoreDependencies

    init(configuration: CoreConfiguration, dependencies: CoreDependencies) {
        self.configuration = configuration
        self.dependencies = dependencies
    }

    // MARK: - Datadog Specific

    /// The client token allowing for data uploads to [Datadog Site](https://docs.datadoghq.com/getting_started/site/).
    var clientToken: String { configuration.clientToken }

    /// The name of the service that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    var service: String { configuration.serviceName }

    /// The name of the environment that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    var env: String { configuration.environment }

    /// The version of the application that data is generated from. Used for [Unified Service Tagging](https://docs.datadoghq.com/getting_started/tagging/unified_service_tagging).
    var version: String { configuration.applicationVersion }

    /// Denotes the mobile application's platform, such as `"ios"` or `"flutter"` that data is generated from.
    ///  - See: Datadog [Reserved Attributes](https://docs.datadoghq.com/logs/log_configuration/attributes_naming_convention/#reserved-attributes).
    var source: String { configuration.source }

    /// The version of Datadog iOS SDK.
    var sdkVersion: String { configuration.sdkVersion }

    /// The name of [CI Visibility](https://docs.datadoghq.com/continuous_integration/) origin.
    /// It is only set if the SDK is running with a context passed from [Swift Tests](https://docs.datadoghq.com/continuous_integration/setup_tests/swift/?tab=swiftpackagemanager) library.
    var ciAppOrigin: String? { configuration.origin }

    // MARK: - Application Specific

    /// The name of the application, read from `Info.plist` (`CFBundleExecutable`).
    var applicationName: String { configuration.applicationName }

    /// Current device information.
    var mobileDevice: MobileDevice { dependencies.mobileDevice }
}
