/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

import DatadogCore
import DatadogRUM
import DatadogSessionReplay

import CatalogUIKit

struct SessionReplayScenario: Scenario {
    private let recordingPipeline: SessionReplayRecordingPipeline

    init(recordingPipeline: SessionReplayRecordingPipeline) {
        self.recordingPipeline = recordingPipeline
    }

    var initialViewController: UIViewController {
        let storyboard = UIStoryboard(name: "Main", bundle: CatalogUIKit.bundle)
        return storyboard.instantiateInitialViewController()!
    }

    func instrument(with info: AppInfo) {
        Datadog.initialize(
            with: .benchmark(info: info),
            trackingConsent: .granted
        )

        RUM.enable(
            with: RUM.Configuration(
                applicationID: info.applicationID,
                uiKitViewsPredicate: DefaultUIKitRUMViewsPredicate(),
                uiKitActionsPredicate: DefaultUIKitRUMActionsPredicate()
            )
        )

        SessionReplay.enable(
            with: SessionReplay.Configuration(
                replaySampleRate: 100,
                textAndInputPrivacyLevel: .maskSensitiveInputs,
                imagePrivacyLevel: .maskNone,
                touchPrivacyLevel: .show,
                featureFlags: featureFlags
            )
        )

        RUMMonitor.shared().addAttribute(forKey: "scenario", value: rumScenarioName)
    }

    private var featureFlags: SessionReplay.Configuration.FeatureFlags {
        switch recordingPipeline {
        case .viewTree:
            return [.heatmaps: true]
        case .compositionTree:
            return [.compositionTreeRecording: true]
        }
    }

    private var rumScenarioName: String {
        switch recordingPipeline {
        case .viewTree:
            return "SessionReplay"
        case .compositionTree:
            return "SessionReplayCompositionTree"
        }
    }
}
