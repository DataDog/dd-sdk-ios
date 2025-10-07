/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

internal class RUMAppLaunchManager {
    internal enum Constants {
        // Maximum time for a long interval between app launches
        static let maxInactivityDuration: TimeInterval = 604_800 // 1 week
        // Maximum time for an erroneous ttid
        static let maxTTIDDuration: TimeInterval = 60 // 1 minute
    }
    // MARK: - Properties

    private unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies

    private var timeToInitialDisplay: Double?

    private lazy var startupTypeHandler = StartupTypeHandler(appStateManager: dependencies.appStateManager)

    // MARK: - Initialization

    init(parent: RUMContextProvider, dependencies: RUMScopeDependencies) {
        self.parent = parent
        self.dependencies = dependencies
    }

    // MARK: - Internal Interface

    func process(_ command: RUMCommand, context: DatadogContext, writer: Writer, activeView: RUMViewScope?) {
        do {
            switch command {
            case let command as RUMTimeToInitialDisplayCommand:
                try writeTTIDVitalEvent(from: command, context: context, writer: writer, activeView: activeView)
            default: break
            }
        } catch {
            dependencies.telemetry.error("RUMAppLaunchManager failed to write the ttid vital event.", error: error)
        }
    }

    // MARK: - Private Methods

    private func writeTTIDVitalEvent(from command: RUMTimeToInitialDisplayCommand, context: DatadogContext, writer: Writer, activeView: RUMViewScope?) throws {
        guard shouldProcess(command: command, context: context),
              let timeToInitialDisplay = timeToInitialDisplay(from: command, context: context) else { return }

        self.timeToInitialDisplay = timeToInitialDisplay

        let attributes = command.globalAttributes
            .merging(command.attributes) { $1 }

        try dependencies.appStateManager.currentAppStateInfo { [weak self] currentAppStateInfo in
            guard let self else {
                return
            }

            let appLaunchMetric: RUMVitalEvent.Vital.AppLaunchProperties.AppLaunchMetric = .ttid
            let startupType = self.startupTypeHandler.startupType(currentAppState: currentAppStateInfo)
            let vital = RUMVitalEvent.Vital.appLaunchProperties(
                value: RUMVitalEvent.Vital.AppLaunchProperties(
                    appLaunchMetric: .ttid,
                    duration: Double(timeToInitialDisplay.toInt64Nanoseconds),
                    id: dependencies.rumUUIDGenerator.generateUnique().toRUMDataFormat,
                    isPrewarmed: context.launchInfo.launchReason == .prewarming,
                    name: appLaunchMetric.name,
                    startupType: startupType
                )
            )

            let vitalEvent = RUMVitalEvent(
                dd: .init(),
                account: .init(context: context),
                application: .init(id: parent.context.rumApplicationID),
                buildId: context.buildId,
                buildVersion: context.buildNumber,
                ciTest: dependencies.ciTest,
                connectivity: .init(context: context),
                context: RUMEventAttributes(contextInfo: attributes),
                date: context.launchInfo.processLaunchDate.timeIntervalSince1970.toInt64Milliseconds,
                ddtags: context.ddTags,
                device: context.normalizedDevice(),
                os: context.os,
                service: context.service,
                session: .init(
                    hasReplay: context.hasReplay,
                    id: parent.context.sessionID.toRUMDataFormat,
                    type: dependencies.sessionType
                ),
                source: .init(rawValue: context.source) ?? .ios,
                synthetics: dependencies.syntheticsTest,
                usr: .init(context: context),
                version: context.version,
                vital: vital
            )

            writer.write(value: vitalEvent)
        }
    }

    private func shouldProcess(command: RUMTimeToInitialDisplayCommand, context: DatadogContext) -> Bool {
        // Ignore command if the time to initial display was already written
        guard self.timeToInitialDisplay == nil else {
            return false
        }

        // Ignore command if the time to initial display is too big
        guard command.time.timeIntervalSince(context.launchInfo.processLaunchDate) < Constants.maxTTIDDuration else {
            return false
        }

        // Ignore app launched in the background by the system or uncertain launch reason
        guard context.launchInfo.launchReason == .userLaunch || context.launchInfo.launchReason == .prewarming else {
            return false
        }

        return true
    }

    private func timeToInitialDisplay(from command: RUMTimeToInitialDisplayCommand, context: DatadogContext) -> TimeInterval? {
        switch context.launchInfo.launchReason {
        case .userLaunch:
            return command.time.timeIntervalSince(context.launchInfo.processLaunchDate)
        case .prewarming:
            guard let runtimeLoadDate = context.launchInfo.launchPhaseDates[.runtimeLoad] else {
                return nil
            }
            return command.time.timeIntervalSince(runtimeLoadDate)
        default:
            return nil
        }
    }
}

private extension RUMVitalEvent.Vital.AppLaunchProperties.AppLaunchMetric {
    var name: String {
        switch self {
        case .ttid: return "time_to_initial_display"
        case .ttfd: return "time_to_full_display"
        }
    }
}

private enum ColdStartRule: CaseIterable {
    case freshInstall
    case appUpdate
    case systemRestart
    case longInactivity
}

private class StartupTypeHandler {
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
                   (currentAppState.appLaunchTime - previousAppStateInfo.appLaunchTime) > RUMAppLaunchManager.Constants.maxInactivityDuration {
                    return .coldStart
                }
            }
        }

        return .warmStart
    }
}
