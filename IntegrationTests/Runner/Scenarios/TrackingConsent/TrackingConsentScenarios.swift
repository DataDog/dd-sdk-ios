/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal
import Datadog

internal class TrackingConsentBaseScenario {
    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews()
            .trackUIKitRUMActions()
            .trackURLSession(firstPartyHosts: ["datadoghq.com"])
    }

    func configureFeatures() {
        guard let tracesEndpoint = Environment.serverMockConfiguration()?.tracesEndpoint else {
            return
        }

        // Register Tracer
        DatadogTracer.initialize(
            configuration: .init(
                sendNetworkInfo: true,
                customIntakeURL: tracesEndpoint
            )
        )
    }
}

/// Tracking consent scenario, which launches the app with `.pending` consent value.
final class TrackingConsentStartPendingScenario: TrackingConsentBaseScenario, TestScenario {
    static let storyboardName = "TrackingConsentScenario"
    let initialTrackingConsent: TrackingConsent = .pending

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        super.configureSDK(builder: builder)
    }
}

/// Tracking consent scenario, which launches the app with `.granted` consent value.
final class TrackingConsentStartGrantedScenario: TrackingConsentBaseScenario, TestScenario {
    static let storyboardName = "TrackingConsentScenario"
    let initialTrackingConsent: TrackingConsent = .granted

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        super.configureSDK(builder: builder)
    }
}
