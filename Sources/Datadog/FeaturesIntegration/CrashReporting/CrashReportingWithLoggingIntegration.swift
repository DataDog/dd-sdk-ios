/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

/// An integration sending crash reports as logs.
internal struct CrashReportingWithLoggingIntegration: CrashReportingIntegration {
    init(loggingFeature: LoggingFeature) {
        // TODO: RUMM-1050 Create `LogOutput`
    }

    func send(crashReport: DDCrashReport, with crashContext: CrashContext) {
        // TODO: RUMM-1050 Send crash report as Log
        // by writting it to the `LogOutput`
        print(
            """
            🍿 Sending Crash Report using Logging integration
            🔥 \(crashReport.type) [\(crashReport.message)]
            🔎 crash context: \(String(describing: crashContext))
            """
        )
    }
}
