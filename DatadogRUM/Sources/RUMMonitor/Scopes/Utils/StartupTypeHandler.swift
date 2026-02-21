/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

internal enum ColdStartRule: String, CaseIterable {
    case freshInstall
    case appUpdate
    case systemRestart
    case longInactivity
}

internal final class StartupTypeHandler {
    enum Constants {
        // Maximum time for a long interval between app launches
        static let maxInactivityDuration: TimeInterval = 604_800 // 1 week
    }
    private let appStateManager: AppStateManaging
    private let telemetryController: AppLaunchMetricController
    private let coldStartRules: [ColdStartRule]

    init(
        appStateManager: AppStateManaging,
        telemetryController: AppLaunchMetricController,
        coldStartRules: [ColdStartRule] = ColdStartRule.allCases
    ) {
        self.appStateManager = appStateManager
        self.telemetryController = telemetryController
        self.coldStartRules = coldStartRules
    }

    func startupType(previousAppState: AppStateInfo?, currentAppState: AppStateInfo) -> RUMVitalAppLaunchEvent.Vital.StartupType {
        for rule in coldStartRules {
            switch rule {
            case .freshInstall:
                if previousAppState == nil {
                    telemetryController.track(coldStartRule: rule)
                    return .coldStart
                }
            case .appUpdate:
                if let previousAppState,
                   previousAppState.appVersion != currentAppState.appVersion {
                    telemetryController.track(coldStartRule: rule)
                    return .coldStart
                }
            case .systemRestart:
                if let previousAppState,
                   previousAppState.systemBootTime < currentAppState.systemBootTime {
                    telemetryController.track(coldStartRule: rule)
                    return .coldStart
                }
            case .longInactivity:
                if let previousAppState,
                   (currentAppState.appLaunchTime - previousAppState.appLaunchTime) > Constants.maxInactivityDuration {
                    telemetryController.track(coldStartRule: rule)
                    return .coldStart
                }
            }
        }

        return .warmStart
    }
}
