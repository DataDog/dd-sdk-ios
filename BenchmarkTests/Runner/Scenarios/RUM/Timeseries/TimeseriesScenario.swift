/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogCore
@_spi(Experimental)
import DatadogRUM
import SwiftUI

struct TimeseriesScenario: Scenario {
    var initialViewController: UIViewController {
        UIHostingController(rootView: RUMAutoContentView())
    }

    func instrumentBaseline(with info: AppInfo) {
        enableRUM(with: info, timeseries: nil)
    }

    func instrument(with info: AppInfo) {
        enableRUM(with: info, timeseries: .default)
    }

    private func enableRUM(with info: AppInfo, timeseries: RUM.Configuration.Timeseries?) {
        Datadog.initialize(
            with: .benchmark(info: info),
            trackingConsent: .granted
        )

        var configuration = RUM.Configuration(
            applicationID: info.applicationID,
            uiKitViewsPredicate: DefaultUIKitRUMViewsPredicate(),
            uiKitActionsPredicate: DefaultUIKitRUMActionsPredicate(),
            swiftUIViewsPredicate: DefaultSwiftUIRUMViewsPredicate(),
            swiftUIActionsPredicate: DefaultSwiftUIRUMActionsPredicate(isLegacyDetectionEnabled: true)
        )
        configuration.timeseries = timeseries

        RUM.enable(with: configuration)

        RUMMonitor.shared().addAttribute(forKey: "scenario", value: "Timeseries")
    }
}
