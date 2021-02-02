/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import CrashReporter
import Datadog

@objc
public class DDCrashReportingPlugin: NSObject, DDCrashReportingPluginType {
    private static var sharedPLCrashReporter: PLCrashReporter?

    override public init() {
        DDCrashReportingPlugin.enableOnce()
    }

    private static func enableOnce() {
        if sharedPLCrashReporter == nil {
            sharedPLCrashReporter = PLCrashReporter(
                configuration: PLCrashReporterConfig(
                    signalHandlerType: .BSD,
                    symbolicationStrategy: .all
                )
            )
            do {
                try sharedPLCrashReporter?.enableAndReturnError()
            } catch {
                print("🔥 Failed to enable `PLCrashReporter`: \(error)")
            }
        }
    }

    // MARK: - DDCrashReportingPluginInterface

    public func readPendingCrashReport(completion: (DDCrashReport?) -> Bool) {
        guard let plCrashReporter = DDCrashReportingPlugin.sharedPLCrashReporter,
              plCrashReporter.hasPendingCrashReport() else {
            _ = completion(nil)
            return
        }

        do {
            let plCrashData = try plCrashReporter.loadPendingCrashReportDataAndReturnError()
            let ddCrashReport = try crashReport(from: plCrashData)
            let wasProcessed = completion(ddCrashReport)

            if wasProcessed {
                try plCrashReporter.purgePendingCrashReportAndReturnError()
            }
        } catch {
            print("🔥 Failed to load pending crash report data: \(error)")
        }
    }

    private func crashReport(from crashData: Data) throws -> DDCrashReport {
        let plCrashReport = try PLCrashReport(data: crashData)

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
