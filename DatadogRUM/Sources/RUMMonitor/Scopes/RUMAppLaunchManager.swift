/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

internal class RUMAppLaunchManager {
    internal enum Constants {
        // Maximum time for an erroneous TTID (Time to Initial Display)
        static let maxTTIDDuration: TimeInterval = 60 // 1 minute
        // Maximum time for an erroneous ttfd
        static let maxTTFDDuration: TimeInterval = 90 // 90 seconds
    }
    // MARK: - Properties

    private unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies

    private var timeToInitialDisplay: Double?
    private var timeToFullDisplay: Double?
    private var startupType: RUMVitalEvent.Vital.AppLaunchProperties.StartupType?

    private lazy var startupTypeHandler = StartupTypeHandler(appStateManager: dependencies.appStateManager)

    // MARK: - Initialization

    init(parent: RUMContextProvider, dependencies: RUMScopeDependencies) {
        self.parent = parent
        self.dependencies = dependencies
    }

    // MARK: - Internal Interface

    func process(_ command: RUMCommand, context: DatadogContext, writer: Writer, activeView: RUMViewScope? = nil) {
        switch command {
        case let command as RUMTimeToInitialDisplayCommand:
            writeTTIDVitalEvent(from: command, context: context, writer: writer, activeView: activeView)
        case let command as RUMTimeToFullDisplayCommand:
            writeTTFDVitalEvent(from: command, context: context, writer: writer, activeView: activeView)
        default: break
        }
    }
}

// MARK: - TTID

private extension RUMAppLaunchManager {
    func writeTTIDVitalEvent(from command: RUMTimeToInitialDisplayCommand, context: DatadogContext, writer: Writer, activeView: RUMViewScope?) {
        guard shouldProcess(command: command, context: context),
              let ttid = time(from: command, context: context)
        else {
            return
        }

        self.timeToInitialDisplay = ttid

        dependencies.appStateManager.currentAppStateInfo { [weak self] currentAppStateInfo in
            guard let self else {
                return
            }

            let attributes = command.globalAttributes
                .merging(command.attributes) { $1 }

            let startupType = self.startupTypeHandler.startupType(currentAppState: currentAppStateInfo)
            self.startupType = startupType

            self.writeVitalEvent(
                duration: Double(ttid.toInt64Nanoseconds),
                appLaunchMetric: .ttid,
                startupType: startupType,
                attributes: attributes,
                context: context,
                writer: writer,
                activeView: activeView
            )

            // The TTFD is always written after the TTID. If it exists already, means it was not written before.
            if let timeToFullDisplay {
                let ttfd = max(ttid, timeToFullDisplay)
                self.writeVitalEvent(
                    duration: Double(ttfd.toInt64Nanoseconds),
                    appLaunchMetric: .ttfd,
                    startupType: startupType,
                    attributes: attributes,
                    context: context,
                    writer: writer,
                    activeView: activeView
                )
            }
        }
    }

    func shouldProcess(command: RUMTimeToInitialDisplayCommand, context: DatadogContext) -> Bool {
        // Ignore command if the time to initial display was already written
        guard self.timeToInitialDisplay == nil else {
            return false
        }

        // Ignore command if the time since the SDK load is too big
        guard let runtimeLoadDate = context.launchInfo.launchPhaseDates[.runtimeLoad],
              command.time.timeIntervalSince(runtimeLoadDate) < Constants.maxTTIDDuration else {
            return false
        }

        // Ignore app launched in the background by the system or uncertain launch reason
        guard context.launchInfo.launchReason == .userLaunch || context.launchInfo.launchReason == .prewarming else {
            return false
        }

        return true
    }

    func time(from command: RUMCommand, context: DatadogContext) -> TimeInterval? {
        switch context.launchInfo.launchReason {
        case .userLaunch:
            return command.time.timeIntervalSince(context.launchInfo.processLaunchDate)
        case .prewarming:
            guard let runtimeLoadDate = context.launchInfo.launchPhaseDates[.runtimeLoad] else {
                dependencies.telemetry.error("Prewarming app launch without runtime load date.")
                return nil
            }
            return command.time.timeIntervalSince(runtimeLoadDate)
        default:
            return nil
        }
    }

    func writeVitalEvent(
        duration: TimeInterval,
        appLaunchMetric: RUMVitalEvent.Vital.AppLaunchProperties.AppLaunchMetric,
        startupType: RUMVitalEvent.Vital.AppLaunchProperties.StartupType,
        attributes: [AttributeKey: AttributeValue],
        context: DatadogContext,
        writer: Writer,
        activeView: RUMViewScope?
    ) {
        let vital = RUMVitalEvent.Vital.appLaunchProperties(
            value: RUMVitalEvent.Vital.AppLaunchProperties(
                appLaunchMetric: appLaunchMetric,
                duration: duration,
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
            view: .init(
                id: (activeView?.viewUUID).orNull.toRUMDataFormat,
                url: activeView?.viewPath ?? ""
            ),
            vital: vital
        )

        writer.write(value: vitalEvent)
    }
}

// MARK: - TTFD

private extension RUMAppLaunchManager {
    func writeTTFDVitalEvent(from command: RUMTimeToFullDisplayCommand, context: DatadogContext, writer: Writer, activeView: RUMViewScope?) {
        guard shouldProcess(command: command, context: context),
              let ttfd = time(from: command, context: context) else { return }

        self.timeToFullDisplay = ttfd

        if let timeToFullDisplay, let timeToInitialDisplay, let startupType {
            let attributes = command.globalAttributes
                .merging(command.attributes) { $1 }
            let ttfd = max(timeToInitialDisplay, timeToFullDisplay)

            self.writeVitalEvent(
                duration: Double(ttfd.toInt64Nanoseconds),
                appLaunchMetric: .ttfd,
                startupType: startupType,
                attributes: attributes,
                context: context,
                writer: writer,
                activeView: activeView
            )
        }
    }

    func shouldProcess(command: RUMTimeToFullDisplayCommand, context: DatadogContext) -> Bool {
        // Ignore command if the time to full display was already written
        guard self.timeToFullDisplay == nil else {
            DD.logger.warn("Time to Full Display was already processed. Make sure the `reportAppFullyDisplayed()` API is only called once.")
            return false
        }

        // Ignore command if the time since the SDK load is too big
        guard let runtimeLoadDate = context.launchInfo.launchPhaseDates[.runtimeLoad],
              command.time.timeIntervalSince(runtimeLoadDate) < Constants.maxTTFDDuration else {
            return false
        }

        return true
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
