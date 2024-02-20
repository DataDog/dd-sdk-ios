/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

internal final class BacktraceReportingFeature: DatadogFeature {
    static var name: String = "backtrace-reporting"

    let messageReceiver: FeatureMessageReceiver = NOPFeatureMessageReceiver()

    /// A type capable of generating backtrace reports.
    let reporter: BacktraceReporting

    /// Creates `BacktraceReportingFeature`.
    /// - Parameter reporter: An external implementation of a type capable of generating backtrace reports.
    init(reporter: BacktraceReporting) {
        self.reporter = reporter
    }
}
