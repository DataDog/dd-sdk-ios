/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogTrace
import DatadogRUM
import DatadogLogs
import DatadogCore

internal class TrackingConsentBaseScenario {
    func configureFeatures() {
        // Enable RUM
        var rumConfig = RUM.Configuration(applicationID: "rum-application-id")
        rumConfig.customEndpoint = Environment.serverMockConfiguration()?.rumEndpoint
        rumConfig.uiKitViewsPredicate = DefaultUIKitRUMViewsPredicate()
        rumConfig.uiKitActionsPredicate = DefaultUIKitRUMActionsPredicate()
        rumConfig.urlSessionTracking = .init()
        RUM.enable(with: rumConfig)

        // Enable Network instrumentation
        URLSessionInstrumentation.trackMetrics(with: .init(delegateClass: CustomURLSessionDelegate.self))

        // Enable Trace
        var traceConfig = Trace.Configuration()
        traceConfig.networkInfoEnabled = true
        traceConfig.customEndpoint = Environment.serverMockConfiguration()?.tracesEndpoint
        Trace.enable(with: traceConfig)

        // Enable Logs
        Logs.enable(
            with: Logs.Configuration(
                customEndpoint: Environment.serverMockConfiguration()?.logsEndpoint
            )
        )
    }
}

/// Tracking consent scenario, which launches the app with `.pending` consent value.
final class TrackingConsentStartPendingScenario: TrackingConsentBaseScenario, TestScenario {
    static let storyboardName = "TrackingConsentScenario"
    let initialTrackingConsent: TrackingConsent = .pending

    override func configureFeatures() {
        super.configureFeatures()
    }
}

/// Tracking consent scenario, which launches the app with `.granted` consent value.
final class TrackingConsentStartGrantedScenario: TrackingConsentBaseScenario, TestScenario {
    static let storyboardName = "TrackingConsentScenario"
    let initialTrackingConsent: TrackingConsent = .granted

    override func configureFeatures() {
        super.configureFeatures()
    }
}
