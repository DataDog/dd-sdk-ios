/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import CrashReporter

/// Builds `DDCrashReport` from `PLCrashReport`.
internal struct DDCrashReportBuilder {
    private let minifier = CrashReportInfoMinifier()
    private let exporter = DDCrashReportExporter()

    func createDDCrashReport(from plCrashReport: PLCrashReport) throws -> DDCrashReport {
        // Read intermediate report:
        var crashReport = try CrashReportInfo(from: plCrashReport)

        // Minify intermediate report:
        minifier.minify(crashReport: &crashReport)

        // Export DDCrashReport:
        return exporter.export(crashReport)
    }
}
