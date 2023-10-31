/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class RUMViewScope: RUMScope, RUMContextProvider {
    struct Constants {
        static let frozenFrameThresholdInNs = (0.7).toInt64Nanoseconds // 700ms
        static let slowRenderingThresholdFPS = 55.0
        /// The pre-warming detection attribute key
        static let activePrewarm = "active_pre_warm"
    }

    // MARK: - Child Scopes

    /// Active Resource scopes, keyed by .resourceKey.
    private(set) var resourceScopes: [String: RUMResourceScope] = [:]
    /// Active User Action scope. There can be only one active user action at a time.
    private(set) var userActionScope: RUMUserActionScope?

    // MARK: - Initialization

    private unowned let parent: RUMContextProvider
    private let dependencies: RUMScopeDependencies
    /// If this is the very first view created in the current app process.
    private let isInitialView: Bool

    /// The value holding stable identity of this RUM View.
    let identity: RUMViewIdentity
    /// View attributes.
    private(set) var attributes: [AttributeKey: AttributeValue]
    /// View custom timings, keyed by name. The value of timing is given in nanoseconds.
    private(set) var customTimings: [String: Int64] = [:]

    /// Feature flags evaluated for the view
    private(set) var featureFlags: [String: Encodable] = [:]

    /// This View's UUID.
    let viewUUID: RUMUUID
    /// The path of this View, used as the `VIEW URL` in RUM Explorer.
    let viewPath: String
    /// The name of this View, used as the `VIEW NAME` in RUM Explorer.
    let viewName: String
    /// The start time of this View.
    let viewStartTime: Date

    /// Server time offset for date correction.
    ///
    /// The offset should be applied to event's timestamp for synchronizing
    /// local time with server time. This time interval value can be added to
    /// any date that needs to be synced. e.g:
    ///
    ///     date.addingTimeInterval(serverTimeOffset)
    ///
    /// The server time offset is freezed per view scope so all child event time
    /// stay relatives to the scope.
    let serverTimeOffset: TimeInterval

    /// Tells if this View is the active one.
    /// `true` for every new started View.
    /// `false` if the View was stopped or any other View was started.
    private(set) var isActiveView = true
    /// Tells if this scope has received the "start" command.
    /// If `didReceiveStartCommand == true` and another "start" command is received for this View this scope is marked as inactive.
    private var didReceiveStartCommand = false

    /// Number of Actions happened on this View.
    private var actionsCount: UInt = 0
    /// Number of Resources tracked by this View.
    private var resourcesCount: UInt = 0
    /// Number of Errors tracked by this View.
    private var errorsCount: UInt = 0
    /// Number of Long Tasks tracked by this View.
    private var longTasksCount: Int64 = 0
    /// Number of Frozen Frames tracked by this View.
    private var frozenFramesCount: Int64 = 0
    /// Number of Frustration tracked by this View.
    private var frustrationCount: Int64 = 0

    /// Current version of this View to use for RUM `documentVersion`.
    private var version: UInt = 0

    /// Whether or not the current call to `process(command:)` should trigger a `sendViewEvent()` with an update.
    /// It can be toggled from inside `RUMResourceScope`/`RUMUserActionScope` callbacks, as they are called from processing `RUMCommand`s inside `process()`.
    private var needsViewUpdate = false

    private let vitalInfoSampler: VitalInfoSampler?

    private var viewPerformanceMetrics: [PerformanceMetric: VitalInfo] = [:]

    init(
        isInitialView: Bool,
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        identity: RUMViewIdentity,
        path: String,
        name: String,
        attributes: [AttributeKey: AttributeValue],
        customTimings: [String: Int64],
        startTime: Date,
        serverTimeOffset: TimeInterval
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.isInitialView = isInitialView
        self.identity = identity
        self.attributes = attributes
        self.customTimings = customTimings
        self.viewUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.viewPath = path
        self.viewName = name
        self.viewStartTime = startTime
        self.serverTimeOffset = serverTimeOffset

        self.vitalInfoSampler = dependencies.vitalsReaders.map {
            .init(
                cpuReader: $0.cpu,
                memoryReader: $0.memory,
                refreshRateReader: $0.refreshRate,
                frequency: $0.frequency
            )
        }
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        var context = parent.context
        context.activeViewID = viewUUID
        context.activeViewPath = viewPath
        context.activeUserActionID = userActionScope?.actionUUID
        context.activeViewName = viewName
        return context
    }

    // MARK: - RUMScope

    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        // Tells if the View did change and an update event should be send.
        needsViewUpdate = false

        // Propagate to User Action scope
        userActionScope = userActionScope?.scope(byPropagating: command, context: context, writer: writer)

        let hasSentNoViewUpdatesYet = version == 0
        if isInitialView, hasSentNoViewUpdatesYet {
            needsViewUpdate = true
        }

        // Apply side effects
        switch command {
        // Application Launch
        case let command as RUMApplicationStartCommand:
            sendApplicationStartAction(on: command, context: context, writer: writer)
            if !isInitialView || viewPath != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL {
                dependencies.telemetry.error(
                    "A RUMApplicationStartCommand got sent to a View other than the ApplicationLaunch view."
                )
            }
            // Application Launch also serves as a StartView command for this view
            didReceiveStartCommand = true
            needsViewUpdate = true

        // Session stop
        case is RUMStopSessionCommand:
            isActiveView = false
            needsViewUpdate = true

        // View commands
        case let command as RUMStartViewCommand where identity.equals(command.identity):
            if didReceiveStartCommand {
                // This is the case of duplicated "start" command. We know that the Session scope has created another instance of
                // the `RUMViewScope` for tracking this View, so we mark this one as inactive.
                isActiveView = false
            }
            didReceiveStartCommand = true
            needsViewUpdate = true
        case let command as RUMStartViewCommand where !identity.equals(command.identity):
            isActiveView = false
            needsViewUpdate = true // sanity update (in case if the user forgets to end this View)
        case let command as RUMStopViewCommand where identity.equals(command.identity):
            isActiveView = false
            needsViewUpdate = true
        case let command as RUMAddViewTimingCommand where isActiveView:
            customTimings[command.timingName] = command.time.timeIntervalSince(viewStartTime).toInt64Nanoseconds
            needsViewUpdate = true

        // Resource commands
        case let command as RUMStartResourceCommand where isActiveView:
            startResource(on: command)

        // User Action commands
        case let command as RUMStartUserActionCommand where isActiveView:
            if userActionScope == nil {
                startContinuousUserAction(on: command)
            } else {
                reportActionDropped(type: command.actionType, name: command.name)
            }
        case let command as RUMAddUserActionCommand where isActiveView:
            if command.actionType == .custom {
                // send it instantly without waiting for child events (e.g. resource associated to this action)
                sendDiscreteCustomUserAction(on: command, context: context, writer: writer)
            } else if userActionScope == nil {
                addDiscreteUserAction(on: command)
            } else {
                reportActionDropped(type: command.actionType, name: command.name)
            }

        // Error command
        case let command as RUMAddCurrentViewErrorCommand where isActiveView:
            sendErrorEvent(on: command, context: context, writer: writer)

        case let command as RUMAddLongTaskCommand where isActiveView:
            sendLongTaskEvent(on: command, context: context, writer: writer)

        case let command as RUMAddFeatureFlagEvaluationCommand where isActiveView:
            addFeatureFlagEvaluation(on: command)
            needsViewUpdate = true

        case let command as RUMUpdatePerformanceMetric where isActiveView:
            updatePerformanceMetric(on: command)

        default:
            break
        }

        // Propagate to Resource scopes
        if let resourceCommand = command as? RUMResourceCommand {
            resourceScopes[resourceCommand.resourceKey] = resourceScopes[resourceCommand.resourceKey]?.scope(
                byPropagating: resourceCommand,
                context: context,
                writer: writer
            )
        }

        // Consider scope state and completion
        if needsViewUpdate {
            sendViewUpdateEvent(on: command, context: context, writer: writer)
        }

        let hasNoPendingResources = resourceScopes.isEmpty
        let shouldComplete = !isActiveView && hasNoPendingResources

        return !shouldComplete
    }

    // MARK: - RUMCommands Processing

    private func startResource(on command: RUMStartResourceCommand) {
        resourceScopes[command.resourceKey] = RUMResourceScope(
            context: context,
            dependencies: dependencies,
            resourceKey: command.resourceKey,
            attributes: command.attributes,
            startTime: command.time,
            serverTimeOffset: serverTimeOffset,
            url: command.url,
            httpMethod: command.httpMethod,
            resourceKindBasedOnRequest: command.kind,
            spanContext: command.spanContext,
            onResourceEventSent: { [weak self] in
                self?.resourcesCount += 1
                self?.needsViewUpdate = true
            },
            onErrorEventSent: { [weak self] in
                self?.errorsCount += 1
                self?.needsViewUpdate = true
            }
        )
    }

    private func startContinuousUserAction(on command: RUMStartUserActionCommand) {
        userActionScope = RUMUserActionScope(
            parent: self,
            dependencies: dependencies,
            name: command.name,
            actionType: command.actionType,
            attributes: command.attributes,
            startTime: command.time,
            serverTimeOffset: serverTimeOffset,
            isContinuous: true,
            onActionEventSent: { [weak self] event in
                self?.onActionEventSent(event)
            }
        )
    }

    private func createDiscreteUserActionScope(on command: RUMAddUserActionCommand) -> RUMUserActionScope {
        return RUMUserActionScope(
            parent: self,
            dependencies: dependencies,
            name: command.name,
            actionType: command.actionType,
            attributes: command.attributes,
            startTime: command.time,
            serverTimeOffset: serverTimeOffset,
            isContinuous: false,
            onActionEventSent: { [weak self] event in
                self?.onActionEventSent(event)
            }
        )
    }

    private func onActionEventSent(_ event: RUMActionEvent) {
        actionsCount += 1
        frustrationCount += event.action.frustration?.type.count.toInt64 ?? 0
        needsViewUpdate = true
    }

    private func addDiscreteUserAction(on command: RUMAddUserActionCommand) {
        userActionScope = createDiscreteUserActionScope(on: command)
    }

    private func sendDiscreteCustomUserAction(on command: RUMAddUserActionCommand, context: DatadogContext, writer: Writer) {
        let customActionScope = createDiscreteUserActionScope(on: command)
        _ = customActionScope.process(
            command: RUMStopUserActionCommand(
                time: command.time,
                attributes: [:],
                actionType: .custom,
                name: nil
            ),
            context: context,
            writer: writer
        )
    }

    private func reportActionDropped(type: RUMActionType, name: String) {
        DD.logger.warn(
            """
            RUM Action '\(type)' on '\(name)' was dropped, because another action is still active for the same view.
            """
        )
    }

    // MARK: - Sending RUM Events

    private func sendApplicationStartAction(on command: RUMApplicationStartCommand, context: DatadogContext, writer: Writer) {
        actionsCount += 1

        var attributes = self.attributes
        var loadingTime: Int64?

        if context.launchTime?.isActivePrewarm == true {
            // Set `active_pre_warm` attribute to true in case
            // of pre-warmed app.
            attributes[Constants.activePrewarm] = true
        } else if let launchTime = context.launchTime?.launchTime {
            // Report Application Launch Time only if not pre-warmed
            loadingTime = launchTime.toInt64Nanoseconds
        } else if let launchDate = context.launchTime?.launchDate {
            // The launchTime can be `nil` if the application is not yet
            // active (UIApplicationDidBecomeActiveNotification). That is
            // the case when instrumenting a SwiftUI application that start
            // a RUM view on `SwiftUI.View/onAppear`.
            //
            // In that case, we consider the time between the application
            // launch and the sdkInitialization as the application loading
            // time.
            loadingTime = command.time.timeIntervalSince(launchDate).toInt64Nanoseconds
        }

        let actionEvent = RUMActionEvent(
            dd: .init(
                action: nil,
                browserSdkVersion: nil,
                configuration: .init(sessionReplaySampleRate: nil, sessionSampleRate: Double(dependencies.sessionSampler.samplingRate)),
                session: .init(plan: .plan1)
            ),
            action: .init(
                crash: .init(count: 0),
                error: .init(count: 0),
                frustration: nil,
                id: dependencies.rumUUIDGenerator.generateUnique().toRUMDataFormat,
                loadingTime: loadingTime,
                longTask: .init(count: 0),
                resource: .init(count: 0),
                target: nil,
                type: .applicationStart
            ),
            application: .init(id: self.context.rumApplicationID),
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            context: .init(contextInfo: attributes),
            date: viewStartTime.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: .init(context: context, telemetry: dependencies.telemetry),
            display: nil,
            os: .init(context: context),
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                type: dependencies.ciTest != nil ? .ciTest : .user
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: nil,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                id: viewUUID.toRUMDataFormat,
                inForeground: nil,
                name: viewName,
                referrer: nil,
                url: viewPath
            )
        )

        if let event = dependencies.eventBuilder.build(from: actionEvent) {
            writer.write(value: event)
            needsViewUpdate = true
        } else {
            actionsCount -= 1
        }
    }

    private func sendViewUpdateEvent(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        version += 1

        // RUMM-3133 Don't override View attributes with commands that are not view related.
        if command is RUMViewScopePropagatableAttributes {
            attributes.merge(rumCommandAttributes: command.attributes)
        }

        let isCrash = (command as? RUMAddCurrentViewErrorCommand).map { $0.isCrash ?? false } ?? false
        // RUMM-1779 Keep view active as long as we have ongoing resources
        let isActive = isActiveView || !resourceScopes.isEmpty
        // RUMM-2079 `time_spent` can't be lower than 1ns
        let timeSpent = max(1e-9, command.time.timeIntervalSince(viewStartTime))
        let cpuInfo = vitalInfoSampler?.cpu
        let memoryInfo = vitalInfoSampler?.memory
        let refreshRateInfo = vitalInfoSampler?.refreshRate
        let isSlowRendered = refreshRateInfo?.meanValue.map { $0 < Constants.slowRenderingThresholdFPS }

        let viewEvent = RUMViewEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .init(sessionReplaySampleRate: nil, sessionSampleRate: Double(dependencies.sessionSampler.samplingRate)),
                documentVersion: version.toInt64,
                pageStates: nil,
                replayStats: .init(
                    recordsCount: context.recordsCountByViewID[viewUUID.toRUMDataFormat],
                    segmentsCount: nil,
                    segmentsTotalRawSize: nil
                ),
                session: .init(plan: .plan1)
            ),
            application: .init(id: self.context.rumApplicationID),
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            context: .init(contextInfo: attributes),
            date: viewStartTime.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: .init(context: context, telemetry: dependencies.telemetry),
            display: nil,
            featureFlags: .init(featureFlagsInfo: featureFlags),
            os: .init(context: context),
            privacy: nil,
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                isActive: self.context.isSessionActive,
                sampledForReplay: nil,
                startPrecondition: nil,
                type: dependencies.ciTest != nil ? .ciTest : .user
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: nil,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                action: .init(count: actionsCount.toInt64),
                cpuTicksCount: cpuInfo?.greatestDiff,
                cpuTicksPerSecond: timeSpent > 1.0 ? cpuInfo?.greatestDiff?.divideIfNotZero(by: Double(timeSpent)) : nil,
                crash: isCrash ? .init(count: 1) : .init(count: 0),
                cumulativeLayoutShift: nil,
                cumulativeLayoutShiftTargetSelector: nil,
                customTimings: customTimings.reduce(into: [:]) { acc, element in
                    acc[sanitizeCustomTimingName(customTiming: element.key)] = element.value
                },
                domComplete: nil,
                domContentLoaded: nil,
                domInteractive: nil,
                error: .init(count: errorsCount.toInt64),
                firstByte: nil,
                firstContentfulPaint: nil,
                firstInputDelay: nil,
                firstInputTargetSelector: nil,
                firstInputTime: nil,
                flutterBuildTime: viewPerformanceMetrics[.flutterBuildTime]?.asFlutterBuildTime(),
                flutterRasterTime: viewPerformanceMetrics[.flutterRasterTime]?.asFlutterRasterTime(),
                frozenFrame: .init(count: frozenFramesCount),
                frustration: .init(count: frustrationCount),
                id: viewUUID.toRUMDataFormat,
                inForegroundPeriods: nil,
                interactionToNextPaint: nil,
                interactionToNextPaintTargetSelector: nil,
                isActive: isActive,
                isSlowRendered: isSlowRendered ?? false,
                jsRefreshRate: viewPerformanceMetrics[.jsFrameTimeSeconds]?.asJsRefreshRate(),
                largestContentfulPaint: nil,
                largestContentfulPaintTargetSelector: nil,
                loadEvent: nil,
                loadingTime: nil,
                loadingType: nil,
                longTask: .init(count: longTasksCount),
                memoryAverage: memoryInfo?.meanValue,
                memoryMax: memoryInfo?.maxValue,
                name: viewName,
                referrer: nil,
                refreshRateAverage: refreshRateInfo?.meanValue,
                refreshRateMin: refreshRateInfo?.minValue,
                resource: .init(count: resourcesCount.toInt64),
                timeSpent: timeSpent.toInt64Nanoseconds,
                url: viewPath
            )
        )

        if let event = dependencies.eventBuilder.build(from: viewEvent) {
            writer.write(value: event, metadata: event.metadata())

            // Update `CrashContext` with recent RUM view (no matter sampling - we want to always
            // have recent information if process is interrupted by crash):
            dependencies.core?.send(
                message: .baggage(
                    key: RUMBaggageKeys.viewEvent,
                    value: event
                )
            )
        } else { // if event was dropped by mapper
            version -= 1
        }
    }

    private func sendErrorEvent(on command: RUMAddCurrentViewErrorCommand, context: DatadogContext, writer: Writer) {
        errorsCount += 1

        let errorEvent = RUMErrorEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .init(sessionReplaySampleRate: nil, sessionSampleRate: Double(dependencies.sessionSampler.samplingRate)),
                session: .init(plan: .plan1)
            ),
            action: self.context.activeUserActionID.map { rumUUID in
                .init(id: .string(value: rumUUID.toRUMDataFormat))
            },
            application: .init(id: self.context.rumApplicationID),
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            context: .init(contextInfo: command.attributes),
            date: command.time.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: .init(context: context, telemetry: dependencies.telemetry),
            display: nil,
            error: .init(
                causes: nil,
                handling: nil,
                handlingStack: nil,
                id: nil,
                isCrash: command.isCrash ?? false,
                message: command.message,
                resource: nil,
                source: command.source.toRUMDataFormat,
                sourceType: command.errorSourceType,
                stack: command.stack,
                type: command.type
            ),
            featureFlags: .init(featureFlagsInfo: featureFlags),
            os: .init(context: context),
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                type: dependencies.ciTest != nil ? .ciTest : .user
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: nil,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                id: self.context.activeViewID.orNull.toRUMDataFormat,
                inForeground: nil,
                name: self.context.activeViewName,
                referrer: nil,
                url: self.context.activeViewPath ?? ""
            )
        )

        if let event = dependencies.eventBuilder.build(from: errorEvent) {
            writer.write(value: event)
            needsViewUpdate = true
        } else {
            errorsCount -= 1
        }
    }

    private func sendLongTaskEvent(on command: RUMAddLongTaskCommand, context: DatadogContext, writer: Writer) {
        let taskDurationInNs = command.duration.toInt64Nanoseconds
        let isFrozenFrame = taskDurationInNs > Constants.frozenFrameThresholdInNs

        let longTaskEvent = RUMLongTaskEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .init(sessionReplaySampleRate: nil, sessionSampleRate: Double(dependencies.sessionSampler.samplingRate)),
                discarded: nil,
                session: .init(plan: .plan1)
            ),
            action: self.context.activeUserActionID.map {
                .init(id: .string(value: $0.toRUMDataFormat))
            },
            application: .init(id: self.context.rumApplicationID),
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            context: .init(contextInfo: command.attributes),
            date: (command.time - command.duration).addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: .init(context: context, telemetry: dependencies.telemetry),
            display: nil,
            longTask: .init(duration: taskDurationInNs, id: nil, isFrozenFrame: isFrozenFrame),
            os: .init(context: context),
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                type: dependencies.ciTest != nil ? .ciTest : .user
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: nil,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                id: self.context.activeViewID.orNull.toRUMDataFormat,
                name: self.context.activeViewName,
                referrer: nil,
                url: self.context.activeViewPath ?? ""
            )
        )

        if let event = dependencies.eventBuilder.build(from: longTaskEvent) {
            writer.write(value: event)
            longTasksCount += 1
            needsViewUpdate = true

            if command.duration.toInt64Nanoseconds > Constants.frozenFrameThresholdInNs {
                frozenFramesCount += 1
            }
        }
    }

    private func sanitizeCustomTimingName(customTiming: String) -> String {
        let sanitized = customTiming.replacingOccurrences(of: "[^a-zA-Z0-9_.@$-]", with: "_", options: .regularExpression)

        if customTiming != sanitized {
            DD.logger.warn(
                """
                Custom timing '\(customTiming)' was modified to '\(sanitized)' to match Datadog constraints.
                """
            )
        }

        return sanitized
    }

    private func addFeatureFlagEvaluation(on command: RUMAddFeatureFlagEvaluationCommand) {
        featureFlags[command.name] = command.value
    }

    private func updatePerformanceMetric(on command: RUMUpdatePerformanceMetric) {
        if viewPerformanceMetrics[command.metric] == nil {
            viewPerformanceMetrics[command.metric] = VitalInfo()
        }
        viewPerformanceMetrics[command.metric]?.addSample(command.value)
    }
}

private extension VitalInfo {
    func asFlutterBuildTime() -> RUMViewEvent.View.FlutterBuildTime {
        return RUMViewEvent.View.FlutterBuildTime(
            average: meanValue ?? 0.0,
            max: maxValue ?? 0.0,
            metricMax: nil,
            min: minValue ?? 0.0
        )
    }

    func asFlutterRasterTime() -> RUMViewEvent.View.FlutterRasterTime {
        return RUMViewEvent.View.FlutterRasterTime(
            average: meanValue ?? 0.0,
            max: maxValue ?? 0.0,
            metricMax: nil,
            min: minValue ?? 0.0
        )
    }

    func asJsRefreshRate() -> RUMViewEvent.View.JsRefreshRate {
        return RUMViewEvent.View.JsRefreshRate(
            average: meanValue.map { $0.inverted } ?? 0,
            max: minValue.map { $0.inverted } ?? 0,
            metricMax: 60.0,
            min: maxValue.map { $0.inverted } ?? 0
        )
    }
}

/// A protocol for `RUMCommand`s that can propagate their attributes to the `RUMViewScope``.
internal protocol RUMViewScopePropagatableAttributes where Self: RUMCommand {
}
