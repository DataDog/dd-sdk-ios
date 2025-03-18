/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import SwiftUI

import DatadogCore
import DatadogRUM

struct RUMManualScenario: Scenario {
    var initialViewController: UIViewController {
        UIHostingController(rootView: RUMManualContentView())
    }

    func instrument(with info: AppInfo) {
        Datadog.initialize(
            with: .benchmark(info: info),
            trackingConsent: .granted
        )

        RUM.enable(
            with: RUM.Configuration(applicationID: info.applicationID)
        )
    }
}
