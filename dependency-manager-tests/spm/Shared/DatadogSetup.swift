/*
* Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
* This product includes software developed at Datadog (https://www.datadoghq.com/).
* Copyright 2019-Present Datadog, Inc.
*/

import DatadogCore
import DatadogLogs
import DatadogTrace
import DatadogCrashReporting

enum DatadogSetup {
    static var logger: LoggerProtocol?
    static func initialize() {
        Datadog.initialize(
            with: Datadog.Configuration(clientToken: "abc", env: "tests"),
            trackingConsent: .granted
        )

        Logs.enable()

        CrashReporting.enable()

        logger = Logger.create(
            with: Logger.Configuration(
                remoteSampleRate: 0,
                consoleLogFormat: .short
            )
        )

        // Trace APIs must be visible:
        Trace.enable()

        logger?.info("It works")
        let span = Tracer.shared().startSpan(operationName: "this too")
        span.finish()
    }
}
