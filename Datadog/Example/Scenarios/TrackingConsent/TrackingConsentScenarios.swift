/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import Datadog

let allTrackingConsentScenarios: [TestScenario.Type] = [
    TrackingConsentStartPendingScenario.self,
    TrackingConsentStartGrantedScenario.self,
]

internal class TrackingConsentBaseScenario {
    func configureSDK(builder: Datadog.Configuration.Builder) {
        _ = builder
            .trackUIKitRUMViews(using: DefaultUIKitRUMViewsPredicate())
            .trackUIKitActions(true)
            .track(firstPartyHosts: ["datadoghq.com"])
    }
}

/// Tracking consent scenario, which launches the app with `.pending` consent value.
final class TrackingConsentStartPendingScenario: TrackingConsentBaseScenario, TestScenario {
    static let storyboardName = "TrackingConsentScenario"
    static func envIdentifier() -> String { "TrackingConsentStartPendingScenario" }
    let initialTrackingConsent: TrackingConsent = .pending

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        super.configureSDK(builder: builder)
    }
}

/// Tracking consent scenario, which launches the app with `.granted` consent value.
final class TrackingConsentStartGrantedScenario: TrackingConsentBaseScenario, TestScenario {
    static let storyboardName = "TrackingConsentScenario"
    static func envIdentifier() -> String { "TrackingConsentStartGrantedScenario" }
    let initialTrackingConsent: TrackingConsent = .granted

    override func configureSDK(builder: Datadog.Configuration.Builder) {
        super.configureSDK(builder: builder)
    }
}
