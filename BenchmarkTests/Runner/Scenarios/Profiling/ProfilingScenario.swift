/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import SwiftUI

import DatadogCore
import DatadogRUM
import DatadogProfiling

struct ProfilingScenario: Scenario {
    var initialViewController: UIViewController {
        UIHostingController(rootView: ProfilingAppLaunchView())
    }

    func prewarm(with info: AppInfo) {
        Datadog.initialize(
            with: .benchmark(info: info),
            trackingConsent: .granted
        )

        Profiling.enable(with: .init(sampleRate: 100))
    }

    func instrument(with info: AppInfo) {
        Datadog.initialize(
            with: .benchmark(info: info),
            trackingConsent: .granted
        )

        RUM.enable(
            with: RUM.Configuration(
                applicationID: info.applicationID
            )
        )

        Profiling.enable(with: .init(sampleRate: 100))
    }
}
