/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import CrashReporter
import Datadog

internal final class PLCrashReporterIntegration: ThirdPartyCrashReporter {
    private let crashReporter: PLCrashReporter

    init() throws {
        self.crashReporter = PLCrashReporter(
            configuration: PLCrashReporterConfig(
                signalHandlerType: .BSD,
                symbolicationStrategy: .all
            )
        )
        try crashReporter.enableAndReturnError()
    }

    func hasPendingCrashReport() -> Bool {
        return crashReporter.hasPendingCrashReport()
    }

    func loadPendingCrashReport() throws -> DDCrashReport {
        let plCrashReportData = try crashReporter.loadPendingCrashReportDataAndReturnError()
        return try ddCrashReport(from: plCrashReportData)
    }

    func purgePendingCrashReport() throws {
        try crashReporter.purgePendingCrashReportAndReturnError()
    }

    // MARK: - Private

    private func ddCrashReport(from crashData: Data) throws -> DDCrashReport {
        let plCrashReport = try PLCrashReport(data: crashData)

        // TODO: RUMM-1053 - add / remove information form this crash report
        return DDCrashReport(
            crashDate: plCrashReport.systemInfo.timestamp,
            signalCode: plCrashReport.signalInfo.code,
            signalName: plCrashReport.signalInfo.name,
            signalDetails: signalDetails(for: plCrashReport.signalInfo.name),
            stackTrace: PLCrashReportTextFormatter.stringValue(
                for: plCrashReport,
                with: PLCrashReportTextFormatiOS
            )
        )
    }

    // TODO: RUMM-1053 - improve / remove this formatting of the signal details
    private func signalDetails(for signalName: String?) -> String? {
        guard let signalName = signalName else {
            return nil
        }

        let signalNames = Mirror(reflecting: sys_signame)
            .children
            .map { $0.value as! UnsafePointer<Int8> } // swiftlint:disable:this force_cast
            .map { String(cString: $0).uppercased() }
        let signalDescription = Mirror(reflecting: sys_siglist)
            .children
            .map { $0.value as! UnsafePointer<Int8> } // swiftlint:disable:this force_cast
            .map { String(cString: $0) }

        if let index = signalNames.firstIndex(where: { signalName == ("SIG"+$0) }) {
            return signalDescription[index]
        }

        return nil
    }
}
