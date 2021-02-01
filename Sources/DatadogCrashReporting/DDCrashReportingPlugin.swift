/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import CrashReporter

public class DDCrashReportingPlugin {
    private static var sharedPLCrashReporter: PLCrashReporter?

    public init?() {
        DDCrashReportingPlugin.sharedPLCrashReporter = PLCrashReporter(
            configuration: PLCrashReporterConfig(
                signalHandlerType: .BSD,
                symbolicationStrategy: .all
            )
        )
    }

    // TODO: RUMM-956 Revamp this by shaping the final API
    public func testIfItWorks() {
        do {
            guard let plCrashReporter = DDCrashReportingPlugin.sharedPLCrashReporter else {
                print("🔥 Failed to instantiate `PLCrashReporter`")
                return
            }
            try plCrashReporter.enableAndReturnError()
            print("✅ Succeded with enabling `PLCrashReporter`")
        } catch {
            print("🔥 Failed to enable `PLCrashReporter`: \(error)")
        }
    }
}
