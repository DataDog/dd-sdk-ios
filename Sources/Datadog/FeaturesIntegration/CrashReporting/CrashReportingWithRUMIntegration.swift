/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

/// An integration sending crash reports as RUM Errors.
internal struct CrashReportingWithRUMIntegration: CrashReportingIntegration {
    init(rumFeature: RUMFeature) {
        // TODO: RUMM-960 Create `RUMEventOutput`
    }

    func send(crashReport: DDCrashReport, with crashContext: CrashContext) {
        // TODO: RUMM-960 Send crash report as RUM Errors (followed by RUM View update)
        // by writting it to the `RUMEventOutput`
        print(
            """
            🍿 Sending Crash Report using RUM integration
            🔥 \(crashReport.signalName ?? "") [\(crashReport.signalDetails ?? "")]
            🔎 crash context: \(String(describing: crashContext))
            """
        )
    }
}
