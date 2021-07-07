/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import CrashReporter
import Datadog

/// Builds `DDCrashReport` from `PLCrashReport`.
internal struct DDCrashReportBuilder {
    private let exporter = DDCrashReportExporter()

    func createDDCrashReport(from plCrashReport: PLCrashReport) throws -> DDCrashReport {
        let crashReport = try CrashReport(from: plCrashReport)
        // TODO: RUMM-1462 Minify number of stack frames and binary images
        return exporter.export(crashReport)
    }
}
