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

    /// Orchestrates the operations, guaranteeing:
    /// - A possible TTFD is always written after a TTID;
    /// - If the TTID is rejected, a pending or future TTFD is discarded and rejected as well;
    /// - If the TTID is missing, a TTFD is never written;
    /// - A maximum of one events of each type is written.
    ///
    /// The wording used has the following meanings:
    /// - Reported: `process(_:context:writer:activeView:)` was called for the given event, but not yet
    /// written to disk.
    /// - Written: The event was written to disk.
    /// - Rejected: Applies to TTID only. The event was explicitly rejected by a check (being longer than a reasonable time, etc).
    /// - Discarded: Applies to TTFD only. The event was either rejected or ignored due to an earlier TTID rejection.
    private struct State {
        /// Keeps the TTID state.
        ///
        /// We need to tell apart between reported and written, since we jump queues between both
        /// operations.
        private enum TTIDState {
            case notReported
            case reported(Double)
            case written(Double)
            case rejected
        }

        /// Keeps the TTFD state.
        private enum TTFDState {
            case notReported
            case reportedWaitingForTTID(TimeToFullDisplay)
            case writtenOrDiscarded
        }

        private var ttidState: TTIDState = .notReported
        private var ttfdState: TTFDState = .notReported

        var canProcessTTID: Bool {
            switch ttidState {
            case .notReported:  true
            default:            false
            }
        }

        var canProcessTTFD: Bool {
            switch ttfdState {
            case .notReported:  true
            default:            false
            }
        }

        mutating func markTTIDAsWritten(_ ttid: Double) {
            ttidState = .written(ttid)
        }

        mutating func markTTIDAsRejected() {
            ttidState = .rejected
            /// If the TTID was rejected (for being longer than a reasonable time, app launch reason not confidently
            /// detected, etc) any TTFD, pending or future, should be discarded.
            ttfdState = .writtenOrDiscarded
        }

        mutating func markTTIDAsReported(_ ttid: Double) {
            ttidState = .reported(ttid)
        }

        mutating func markTTFDAsReported(_ ttfd: TimeToFullDisplay) {
            ttfdState = .reportedWaitingForTTID(ttfd)
        }

        mutating func markTTFDAsWritten() {
            ttfdState = .writtenOrDiscarded
        }

        var pendingTTFD: TimeToFullDisplay? {
            switch ttfdState {
            case .reportedWaitingForTTID(let timeToFullDisplay): timeToFullDisplay
            default: nil
            }
        }

        var reportedOrWrittenTtid: Double? {
            switch ttidState {
            case .reported(let ttid), .written(let ttid): ttid
            case .notReported, .rejected: nil
            }
        }

        var writtenTTID: Double? {
            switch ttidState {
            case .written(let ttid): ttid
            case .notReported, .rejected, .reported: nil
            }
        }
    }

    @ReadWriteLock
    private var state = State()

    private struct TimeToFullDisplay {
        let duration: TimeInterval
        let vitalId: String
        let attributes: [AttributeKey: AttributeValue]
        let view: RUMVitalAppLaunchEvent.View
        let context: DatadogContext
        let profiling: DDProfiling?
    }
    // MARK: - Properties

    private unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies
    private let telemetryController: AppLaunchMetricController
    private let sanitizer = RUMEventSanitizer()
    private var startupType: RUMVitalAppLaunchEvent.Vital.StartupType?

    private lazy var startupTypeHandler = StartupTypeHandler(telemetryController: telemetryController)

    // MARK: - Initialization

    init(
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        telemetryController: AppLaunchMetricController
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.telemetryController = telemetryController
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
    private func writeTTIDVitalEvent(from command: RUMTimeToInitialDisplayCommand, context: DatadogContext, writer: Writer, activeView: RUMViewScope?) {
        guard shouldProcess(command: command, context: context),
              let ttid = time(from: command, context: context)
        else {
            state.markTTIDAsRejected()
            return
        }

        state.markTTIDAsReported(ttid)
        let ttidVitalId = dependencies.rumUUIDGenerator.generateUnique().toRUMDataFormat
        let profiling = context.additionalContext(ofType: ProfilingContext.self)?.ddProfiling

        if let timeToFullDisplay = state.pendingTTFD {
            // TTID closes app-launch profiling, so only a TTFD reported earlier is sent here.
            sendTTFDMessageToProfiler(ttfd: timeToFullDisplay, ttid: ttid)
        }

        sendTTIDMessageToProfiler(
            vital: .init(
                id: ttidVitalId,
                name: RUMVitalAppLaunchEvent.Vital.AppLaunchMetric.ttid.name,
                date: context.launchInfo.processLaunchDate,
                serverTimeOffset: context.serverTimeOffset,
                duration: ttid.dd.toInt64Nanoseconds
            )
        )

        // Running on core-context queue
        dependencies.appStateManager.previousAppStateInfo { [weak self] previousAppStateInfo in
            // Running on app-state-manager queue
            self?.dependencies.appStateManager.currentAppStateInfo { [weak self] currentAppStateInfo in
                // Running on core-context queue
                guard let self else {
                    return
                }

                let attributes = command.globalAttributes
                    .merging(command.attributes) { $1 }

                let startupType = self.startupTypeHandler.startupType(previousAppState: previousAppStateInfo, currentAppState: currentAppStateInfo)
                self.startupType = startupType

                self.writeVitalEvent(
                    vitalId: ttidVitalId,
                    duration: Double(ttid.dd.toInt64Nanoseconds),
                    appLaunchMetric: .ttid,
                    startupType: startupType,
                    attributes: attributes,
                    context: context,
                    writer: writer,
                    view: .init(activeView: activeView),
                    profiling: profiling
                )

                self.state.markTTIDAsWritten(ttid)

                // The TTFD is always written after the TTID. If it exists already, means it was not written before.
                if let timeToFullDisplay = state.pendingTTFD {
                    let ttfd = max(ttid, timeToFullDisplay.duration)
                    self.writeVitalEvent(
                        vitalId: timeToFullDisplay.vitalId,
                        duration: Double(ttfd.dd.toInt64Nanoseconds),
                        appLaunchMetric: .ttfd,
                        startupType: startupType,
                        attributes: timeToFullDisplay.attributes,
                        context: timeToFullDisplay.context,
                        writer: writer,
                        view: timeToFullDisplay.view,
                        profiling: timeToFullDisplay.profiling
                    )

                    telemetryController.trackTTFD(duration: ttfd.dd.toInt64Nanoseconds)
                    self.state.markTTFDAsWritten()
                }

                telemetryController.sendMetric()
            }
        }
    }

    private func shouldProcess(command: RUMTimeToInitialDisplayCommand, context: DatadogContext) -> Bool {
        // Ignore command if the time to initial display was already written
        guard state.canProcessTTID else {
            telemetryController.incrementTTIDCounter()
            return false
        }

        // Ignore command if the time since the SDK load exceeds the limit
        let launchPhase: LaunchPhase = context.launchInfo.launchReason == .userLaunch ? .processLaunch : .runtimeLoad
        guard let runtimeLoadDate = context.launchInfo.launchPhaseDates[launchPhase],
              (0..<Constants.maxTTIDDuration).contains(command.time.timeIntervalSince(runtimeLoadDate)) else {
            telemetryController.send(metric: .largeTTID(
                context: context,
                duration: command.time.timeIntervalSince(context.launchInfo.processLaunchDate)
            ))
            return false
        }

        // Ignore app launched in the background by the system or uncertain launch reason
        guard context.launchInfo.launchReason == .userLaunch || context.launchInfo.launchReason == .prewarming else {
            telemetryController.send(metric: .launchNotSupported(
                context: context,
                duration: command.time.timeIntervalSince(context.launchInfo.processLaunchDate)
            ))
            return false
        }

        return true
    }

    private func time(from command: RUMCommand, context: DatadogContext) -> TimeInterval? {
        switch context.launchInfo.launchReason {
        case .userLaunch:
            return command.time.timeIntervalSince(context.launchInfo.processLaunchDate)
        case .prewarming:
            guard let runtimeLoadDate = context.launchInfo.launchPhaseDates[.runtimeLoad] else {
                telemetryController.telemetry.error("Prewarming app launch without runtime load date.")
                return nil
            }
            return command.time.timeIntervalSince(runtimeLoadDate)
        default:
            return nil
        }
    }

    private func writeVitalEvent(
        vitalId: String,
        duration: TimeInterval,
        appLaunchMetric: RUMVitalAppLaunchEvent.Vital.AppLaunchMetric,
        startupType: RUMVitalAppLaunchEvent.Vital.StartupType,
        attributes: [AttributeKey: AttributeValue],
        context: DatadogContext,
        writer: Writer,
        view: RUMVitalAppLaunchEvent.View,
        profiling: DDProfiling? = nil
    ) {
        let vital = RUMVitalAppLaunchEvent.Vital(
            appLaunchMetric: appLaunchMetric,
            duration: duration,
            id: vitalId,
            isPrewarmed: context.launchInfo.launchReason == .prewarming,
            name: appLaunchMetric.name,
            startupType: startupType
        )

        let vitalEvent = RUMVitalAppLaunchEvent(
            dd: .init(profiling: profiling),
            account: .init(context: context),
            application: .init(id: parent.context.rumApplicationID),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            context: RUMEventAttributes(contextInfo: attributes),
            date: context.launchInfo.processLaunchDate
                .addingTimeInterval(context.serverTimeOffset)
                .timeIntervalSince1970.dd.toInt64Milliseconds,
            ddtags: context.ddTags,
            device: context.normalizedDevice(),
            os: context.os,
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                hasTimeseries: dependencies.timeseriesCollector?.hasCollectedData(sessionID: parent.context.sessionID.toRUMDataFormat) ?? false,
                id: parent.context.sessionID.toRUMDataFormat,
                isMainProcess: context.applicationBundleType != .iOSAppExtension,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
            usr: .init(context: context),
            version: context.version,
            view: view,
            vital: vital
        )

        let sanitizedVitalEvent = sanitizer.sanitize(event: vitalEvent)
        // Eventually writes in ios-sdk-read-write queue
        writer.write(value: sanitizedVitalEvent)
        telemetryController.track(ttidEvent: sanitizedVitalEvent, context: context)
    }

    private func sendTTIDMessageToProfiler(vital: Vital) {
        let contextAttributes: [String: Encodable] = parent.rumContextAttributes
        dependencies.featureScope.send(message: .payload(TTIDMessage(attributes: contextAttributes, ttid: vital)))
    }
}

// MARK: - TTFD

private extension RUMAppLaunchManager {
    private func writeTTFDVitalEvent(from command: RUMTimeToFullDisplayCommand, context: DatadogContext, writer: Writer, activeView: RUMViewScope?) {
        guard shouldProcess(command: command, context: context),
              let ttfd = time(from: command, context: context) else { return }

        let timeToFullDisplay = TimeToFullDisplay(
            duration: state.reportedOrWrittenTtid.map { max($0, ttfd) } ?? ttfd,
            vitalId: dependencies.rumUUIDGenerator.generateUnique().toRUMDataFormat,
            attributes: command.globalAttributes.merging(command.attributes) { $1 },
            // Captured now so a TTFD held until the TTID completes keeps its own view and context.
            view: RUMVitalAppLaunchEvent.View(activeView: activeView),
            context: context,
            profiling: context.additionalContext(ofType: ProfilingContext.self)?.ddProfiling,
        )

        state.markTTFDAsReported(timeToFullDisplay)

        if let ttid = state.reportedOrWrittenTtid {
            sendTTFDMessageToProfiler(ttfd: timeToFullDisplay, ttid: ttid)
        }

        if let ttid = state.writtenTTID {
            if let startupType {
                self.writeVitalEvent(
                    vitalId: timeToFullDisplay.vitalId,
                    duration: Double(timeToFullDisplay.duration.dd.toInt64Nanoseconds),
                    appLaunchMetric: .ttfd,
                    startupType: startupType,
                    attributes: timeToFullDisplay.attributes,
                    context: timeToFullDisplay.context,
                    writer: writer,
                    view: timeToFullDisplay.view,
                    profiling: timeToFullDisplay.profiling
                )

                state.markTTFDAsWritten()
            }
        }
    }

    private func shouldProcess(command: RUMTimeToFullDisplayCommand, context: DatadogContext) -> Bool {
        // Ignore command if the time to full display was already written
        guard state.canProcessTTFD else {
            return false
        }

        // Ignore command if the time since the SDK load is too big
        let launchPhase: LaunchPhase = context.launchInfo.launchReason == .userLaunch ? .processLaunch : .runtimeLoad
        guard let runtimeLoadDate = context.launchInfo.launchPhaseDates[launchPhase],
              (0..<Constants.maxTTFDDuration).contains(command.time.timeIntervalSince(runtimeLoadDate)) else {
            return false
        }

        return true
    }

    private func sendTTFDMessageToProfiler(ttfd: TimeToFullDisplay, ttid: Double) {
        let ttfdVital = Vital(
            id: ttfd.vitalId,
            name: RUMVitalAppLaunchEvent.Vital.AppLaunchMetric.ttfd.name,
            date: ttfd.context.launchInfo.processLaunchDate,
            serverTimeOffset: ttfd.context.serverTimeOffset,
            duration: max(ttid, ttfd.duration).dd.toInt64Nanoseconds
        )

        var contextAttributes: [String: Encodable] = parent.rumContextAttributes

        if ttfd.view.id == RUMUUID.nullUUID.toRUMDataFormat {
            contextAttributes.removeValue(forKey: RUMCoreContext.IDs.viewID)
            contextAttributes.removeValue(forKey: RUMCoreContext.IDs.viewName)
        } else {
            contextAttributes[RUMCoreContext.IDs.viewID] = [ttfd.view.id]
            contextAttributes[RUMCoreContext.IDs.viewName] = ttfd.view.name.map { [$0] }
        }

        dependencies.featureScope.send(message: .payload(OperationMessage(attributes: contextAttributes, operation: ttfdVital)))
    }
}

private extension RUMVitalAppLaunchEvent.View {
    init(activeView: RUMViewScope?) {
        self.init(
            id: (activeView?.viewUUID).orNull.toRUMDataFormat,
            name: activeView?.viewName,
            url: activeView?.viewPath ?? ""
        )
    }
}

private extension RUMVitalAppLaunchEvent.Vital.AppLaunchMetric {
    var name: String {
        switch self {
        case .ttid: return "time_to_initial_display"
        case .ttfd: return "time_to_full_display"
        }
    }
}
