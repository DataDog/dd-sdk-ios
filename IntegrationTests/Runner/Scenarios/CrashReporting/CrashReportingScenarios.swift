/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import UIKit

import DatadogCore
import DatadogRUM
import DatadogCrashReporting

/// Scenario that launches single-view app which can cause a crash and/or upload the crash report to Datadog.
/// It includes the condition determined by crash report file presence:
/// * if the file is not there, the UI for crashing the app is presented,
/// * if the file is there, the UI for crashing the app is presented and _"Sending crash report..."_ label is shown.
///
/// To test this scenario manually:
///  → disconnect debugger → run the Example app → tap the crash button  → run again to have the crash report uploaded.
internal class CrashReportingBaseScenario {
    static let storyboardName = "CrashReportingScenario"

    let hadPendingCrashReportDataOnStartup: Bool

    init() {
        // The scenario gets instantiated on app startup, so this value is captured
        // before the SDK gets a chance to read & purge the crash report file.
        hadPendingCrashReportDataOnStartup = PersistenceHelpers.hasPendingCrashReportData()
    }
}

/// A `CrashReportingScenario` which uploads the crash report as RUM Error.
final class CrashReportingCollectOrSendWithRUMScenario: CrashReportingBaseScenario, TestScenario {
    class CustomPredicate: UIKitRUMViewsPredicate {
        private let defaultPredicate = DefaultUIKitRUMViewsPredicate()

        func rumView(for viewController: UIViewController) -> RUMView? {
            return defaultPredicate.rumView(for: viewController).flatMap { defaultRUMView in
                return RUMView(
                    name: defaultRUMView.name,
                    attributes: [
                        "custom-attribute": "This attribute will be attached to crash report."
                    ]
                )
            }
        }
    }

    func rumErrorEventMapper(event: RUMErrorEvent) -> RUMErrorEvent? {
        var event = event
        event.error.fingerprint = "mapped fingerprint"
        return event
    }

    func configureFeatures() {
        var rumConfig = RUM.Configuration(applicationID: "rum-application-id")
        rumConfig.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        rumConfig.uiKitViewsPredicate = CustomPredicate()
        rumConfig.errorEventMapper = rumErrorEventMapper

        RUM.enable(with: rumConfig)

        CrashReporting._internal.ks_enable()
    }
}
