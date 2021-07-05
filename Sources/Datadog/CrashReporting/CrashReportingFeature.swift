/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates and owns components enabling Crash Reporting feature.
internal final class CrashReportingFeature {
    /// Single, shared instance of `CrashReportingFeature`.
    static var instance: CrashReportingFeature?

    /// Tells if the feature was enabled by the user in the SDK configuration.
    static var isEnabled: Bool { instance != nil }

    // MARK: - Configuration

    let configuration: FeaturesConfiguration.CrashReporting

    // MARK: - Dependencies

    /// Publishes recent `ConsentProvider` value so it can be persisted in `CrashContext`.
    let consentProvider: ConsentProvider
    /// Publishes recent `UserInfo` value so it can be persisted in `CrashContext`.
    let userInfoProvider: UserInfoProvider
    /// Publishes recent `NetworkConnectionInfo` value so it can be persisted in `CrashContext`.
    let networkConnectionInfoProvider: NetworkConnectionInfoProviderType
    /// Publishes recent `CarrierInfo` value so it can be persisted in `CrashContext`.
    let carrierInfoProvider: CarrierInfoProviderType
    /// Publishes recent `RUMEvent<RUMViewEvent>` value so it can be persisted in `CrashContext`.
    let rumViewEventProvider: ValuePublisher<RUMEvent<RUMViewEvent>?>

    init(
        configuration: FeaturesConfiguration.CrashReporting,
        commonDependencies: FeaturesCommonDependencies
    ) {
        self.configuration = configuration
        self.consentProvider = commonDependencies.consentProvider
        self.userInfoProvider = commonDependencies.userInfoProvider
        self.networkConnectionInfoProvider = commonDependencies.networkConnectionInfoProvider
        self.carrierInfoProvider = commonDependencies.carrierInfoProvider
        self.rumViewEventProvider = ValuePublisher(initialValue: nil)
    }

#if DD_SDK_COMPILED_FOR_TESTING
    func deinitialize() {
        CrashReportingFeature.instance = nil
    }
#endif
}
