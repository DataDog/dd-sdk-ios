/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Datadog
import DatadogCrashReporting

/// Scenario that launches single-view app which conditionally causes the a crash or uploads the crash report to Datadog.
/// The condition is determined by crash report file presence:
/// * if the file is not there, the UI for crashing the app is presented,
/// * if the file is there, the UI for uploading the crash repot is shown.
///
/// To test this scenario manually:
///  → disconnect debugger → run the Example app so it presents "Crash The App" button → crash  → run again.
final class CrashReportingCollectOrSendScenario: TestScenario {
    static let storyboardName = "CrashReportingScenario"

    let hadPendingCrashReportDataOnStartup: Bool

    init() {
        // The scenario gets instantiated on app startup, so this value is captured
        // before the SDK gets a chance to read & purge the crash report file.
        hadPendingCrashReportDataOnStartup = PersistenceHelpers.hasPendingCrashReportData()
    }

    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews()
            .enableCrashReporting(using: DDCrashReportingPlugin())
    }
}
