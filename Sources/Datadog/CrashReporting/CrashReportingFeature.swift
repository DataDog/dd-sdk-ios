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

    let consentProvider: ConsentProvider

    // TODO: RUMM-1049 Bundle `UserInfoProvider`, `NetworkInfoProvider` and `CarrierInfoProvider`
    // for enriching the `CrashContext`

    init(
        configuration: FeaturesConfiguration.CrashReporting,
        commonDependencies: FeaturesCommonDependencies
    ) {
        self.configuration = configuration
        self.consentProvider = commonDependencies.consentProvider
    }
}
