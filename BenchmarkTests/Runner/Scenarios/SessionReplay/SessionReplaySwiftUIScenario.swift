/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit
import SwiftUI

import DatadogCore
import DatadogRUM
import DatadogSessionReplay

import CatalogSwiftUI

struct SessionReplaySwiftUIScenario: Scenario {
    var initialViewController: UIViewController {
        UIHostingController(rootView: CatalogSwiftUI.ContentView(monitor: DatadogMonitor()))
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

        SessionReplay.enable(
            with: SessionReplay.Configuration(
                replaySampleRate: 100,
                textAndInputPrivacyLevel: .maskSensitiveInputs,
                imagePrivacyLevel: .maskNone,
                touchPrivacyLevel: .show,
                featureFlags: [.swiftui: true]
            )
        )

        RUMMonitor.shared().addAttribute(forKey: "scenario", value: "SessionReplaySwiftUI")
    }
}

private struct DatadogMonitor: CatalogSwiftUI.DatadogMonitor {
    func viewModifier(name: String) -> AnyViewModifier {
        AnyViewModifier { content in
            content.trackRUMView(name: name)
        }
    }

    func actionModifier(name: String) -> AnyViewModifier {
        AnyViewModifier { content in
            content.trackRUMTapAction(name: name)
        }
    }
}
