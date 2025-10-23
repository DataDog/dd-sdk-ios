/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

internal enum ColdStartRule: CaseIterable {
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
    private let coldStartRules: [ColdStartRule]

    init(
        appStateManager: AppStateManaging,
        coldStartRules: [ColdStartRule] = ColdStartRule.allCases
    ) {
        self.appStateManager = appStateManager
        self.coldStartRules = coldStartRules
    }

    func startupType(currentAppState: AppStateInfo) -> RUMVitalEvent.Vital.AppLaunchProperties.StartupType {
        for rule in coldStartRules {
            switch rule {
            case .freshInstall:
                if appStateManager.previousAppStateInfo == nil {
                    return .coldStart
                }
            case .appUpdate:
                if let previousAppStateInfo = appStateManager.previousAppStateInfo,
                   previousAppStateInfo.appVersion != currentAppState.appVersion {
                    return .coldStart
                }
            case .systemRestart:
                if let previousAppStateInfo = appStateManager.previousAppStateInfo,
                   previousAppStateInfo.systemBootTime < currentAppState.systemBootTime {
                    return .coldStart
                }
            case .longInactivity:
                if let previousAppStateInfo = appStateManager.previousAppStateInfo,
                   (currentAppState.appLaunchTime - previousAppStateInfo.appLaunchTime) > Constants.maxInactivityDuration {
                    return .coldStart
                }
            }
        }

        return .warmStart
    }
}
