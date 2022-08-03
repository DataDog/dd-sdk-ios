/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Creates and owns components enabling Crash Reporting feature.
internal final class CrashReportingFeature {
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
    /// Publishes recent `RUMViewEvent` value so it can be persisted in `CrashContext`.
    /// It will provide `nil` until first view is tracked.
    let rumViewEventProvider: ValuePublisher<RUMViewEvent?>
    /// Publishes recent RUM session state so it can be persisted in `CrashContext`.
    /// It will be used to decide if and how to track crashes which happen while there was no active view.
    let rumSessionStateProvider: ValuePublisher<RUMSessionState?>
    /// Publishes changes to app "foreground" / "background" state.
    let appStateListener: AppStateListening

    init(
        configuration: FeaturesConfiguration.CrashReporting,
        commonDependencies: FeaturesCommonDependencies
    ) {
        self.configuration = configuration
        self.consentProvider = commonDependencies.consentProvider
        self.userInfoProvider = commonDependencies.userInfoProvider
        self.networkConnectionInfoProvider = commonDependencies.networkConnectionInfoProvider
        self.carrierInfoProvider = commonDependencies.carrierInfoProvider
        self.rumViewEventProvider = ValuePublisher(initialValue: nil) // `nil` by default, because there cannot be any RUM view at this ponit
        self.rumSessionStateProvider = ValuePublisher(initialValue: nil) // `nil` by default, because there cannot be any RUM session at this ponit
        self.appStateListener = commonDependencies.appStateListener
    }
}
