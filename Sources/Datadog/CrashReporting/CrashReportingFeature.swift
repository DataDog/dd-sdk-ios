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

    // TODO: RUMM-960 / RUMM-1050 Bundle dependencies required for sending Crash Reports to Datadog

    init(configuration: FeaturesConfiguration.CrashReporting) {
        self.configuration = configuration
    }
}
