/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

public final class DatadogCrashReporter {
    /// Initializes the Datadog Crash Reporter.
    public static func initialize(in core: DatadogCoreProtocol = defaultDatadogCore) {
        do {
            let contextProvider = CrashContextCoreProvider()

            let reporter = CrashReportingFeature(
                crashReportingPlugin: PLCrashReporterPlugin(),
                crashContextProvider: contextProvider,
                sender: MessageBusSender(core: core),
                messageReceiver: contextProvider
            )

            try core.register(feature: reporter)

            reporter.sendCrashReportIfFound()

            TelemetryCore(core: core)
                .configuration(trackErrors: true)
        } catch {
            consolePrint("\(error)")
        }
    }
}

@available(swift, obsoleted: 1) @objc(DatadogCrashReporter)
public final class objc_DatadogCrashReporter: NSObject {

    @objc
    public static func enable() {
        DatadogCrashReporter.initialize()
    }
}
