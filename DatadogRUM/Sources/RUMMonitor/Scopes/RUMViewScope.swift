/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

public class RUMViewScope: RUMScope, RUMContextProvider {
    struct Constants {
        static let frozenFrameThresholdInNs = (0.7).toInt64Nanoseconds // 700ms
        static let slowRenderingThresholdFPS = 55.0
        static let minimumTimeSpentForRates = 1.0 // 1s
        /// Minimum duration of a view (1ns). Prevents negative durations and serves as placeholder value assigned when view starts.
        static let minimumTimeSpent: TimeInterval = 1e-9 // 1ns
        /// The pre-warming detection attribute key
        static let activePrewarm = "active_pre_warm"
    }

    // MARK: - Child Scopes

    /// Active Resource scopes, keyed by .resourceKey.
    private(set) var resourceScopes: [String: RUMResourceScope] = [:] {
        didSet {
             resourceScopes.forEach {
                 resourceEvents.append(($1.startTime.timeIntervalSince(viewStartTime), $1.duration))
             }
        }
   }

    /// Active User Action scope. There can be only one active user action at a time.
    private(set) var userActionScope: RUMUserActionScope? {
        didSet {
            guard let userActionScope else {
                return
            }

            self.userEvents.append((userActionScope.startTime.timeIntervalSince(viewStartTime), userActionScope.duration))
        }
    }

    // MARK: - Initialization

    private unowned let parent: RUMContextProvider

    /// Container bundling dependencies for this scope.
    let dependencies: RUMScopeDependencies

    /// If this is the very first view created in the current app process.
    private let isInitialView: Bool

    /// The index of this view within its session (0 for the first view).
    private let viewIndexInSession: Int

    /// If this view ever had session replay
    private var hasReplay: Bool

    /// The value holding stable identity of this RUM View.
    let identity: ViewIdentifier
    /// View attributes.
    private(set) var attributes: [AttributeKey: AttributeValue] = [:]
    /// Internal view attributes - used by cross platform frameworks and should not be propagated to events
    private(set) var internalAttributes: [AttributeKey: AttributeValue] = [:]
    /// View custom timings, keyed by name. The value of timing is given in nanoseconds.
    private(set) var customTimings: [String: Int64] = [:]

    /// Feature flags evaluated for the view
    private(set) var featureFlags: [String: Encodable] = [:]

    /// This View's UUID.
    let viewUUID: RUMUUID
    /// The path of this View, used as the `VIEW URL` in RUM Explorer.
    let viewPath: String
    /// The name of this View, used as the `VIEW NAME` in RUM Explorer.
    public let viewName: String
    /// The start time of this View.
    let viewStartTime: Date
    /// The load time of this View.
    private(set) var viewLoadingTime: TimeInterval?

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
    private(set) var isActiveView = true {
        didSet {
            if oldValue && !isActiveView {
                networkSettledMetric.trackViewWasStopped()
            }
        }
    }
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

    let vitalInfoSampler: VitalInfoSampler?

    private var viewPerformanceMetrics: [PerformanceMetric: VitalInfo] = [:]

    /// Time-to-Network-Settled metric for this view.
    private let networkSettledMetric: TNSMetricTracking
    /// Interaction-to-Next-View metric for this view.
    private var interactionToNextViewMetric: INVMetricTracking?
    /// Tracks "RUM View Ended" metric for this view.
    private let viewEndedMetric: ViewEndedController
    /// Tracks "View Hitches" for this view.
    let viewHitchesReader: (ViewHitchesModel & RenderLoopReader)?
    /// Tracks "View Hangs" for this view.
    public var totalAppHangDuration: Double = 0.0

    public var resourceEvents: [(CGFloat, TimeInterval)] = []

    public var userEvents: [(CGFloat, TimeInterval)] = []

    public var hangs: [(CGFloat, TimeInterval)] = []

    public var memoryValue: Double? { self.vitalInfoSampler?.memory.currentValue }

    public var viewHitches: [(start: Int64, duration: Int64)]? { viewHitchesReader?.dataModel.hitches.map { $0 } }

    public var hitchesDuration: Double { self.viewHitchesReader?.dataModel.hitchesDuration ?? 0 }

    public var timeSpent: Double { Date().timeIntervalSince(viewStartTime) }

    private var accessibilityReader: AccessibilityReading?

    init(
        isInitialView: Bool,
        parent: RUMContextProvider,
        dependencies: RUMScopeDependencies,
        identity: ViewIdentifier,
        path: String,
        name: String,
        customTimings: [String: Int64],
        startTime: Date,
        serverTimeOffset: TimeInterval,
        interactionToNextViewMetric: INVMetricTracking?,
        viewIndexInSession: Int
    ) {
        self.parent = parent
        self.dependencies = dependencies
        self.isInitialView = isInitialView
        self.hasReplay = false
        self.identity = identity
        self.customTimings = customTimings
        self.viewUUID = dependencies.rumUUIDGenerator.generateUnique()
        self.viewPath = path
        self.viewName = name
        self.viewStartTime = startTime
        self.serverTimeOffset = serverTimeOffset
        self.interactionToNextViewMetric = interactionToNextViewMetric
        self.viewIndexInSession = viewIndexInSession
        self.accessibilityReader = dependencies.accessibilityReader

        self.vitalInfoSampler = dependencies.vitalsReaders.map {
            .init(
                cpuReader: $0.cpu,
                memoryReader: $0.memory,
                refreshRateReader: $0.refreshRate,
                frequency: $0.frequency
            )
        }
        self.networkSettledMetric = dependencies.networkSettledMetricFactory(viewStartTime, viewName)
        interactionToNextViewMetric?.trackViewStart(at: startTime, name: name, viewID: viewUUID)

        self.viewEndedMetric = dependencies.viewEndedMetricFactory()
        self.viewHitchesReader = dependencies.viewHitchesReaderFactory()

        if let viewHitchesReader {
            dependencies.renderLoopObserver?.register(viewHitchesReader)
        }

        // Notify Synthetics if needed
        if dependencies.syntheticsTest != nil && self.context.sessionID != .nullUUID {
            NSLog("_dd.session.id=" + self.context.sessionID.toRUMDataFormat)
            NSLog("_dd.application.id=" + self.context.rumApplicationID)
            NSLog("_dd.view.id=" + self.viewUUID.toRUMDataFormat)
        }
    }

    deinit {
        if let viewHitchesReader {
            dependencies.renderLoopObserver?.unregister(viewHitchesReader)
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
}

// MARK: - RUMCommands Processing

extension RUMViewScope {
    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        // Tells if the View did change and an update event should be send.
        needsViewUpdate = false

        // Propagate to User Action scope
        userActionScope = userActionScope?.scope(
            byPropagating: command,
            context: context,
            writer: writer
        )

        let hasSentNoViewUpdatesYet = version == 0
        if isInitialView, hasSentNoViewUpdatesYet {
            needsViewUpdate = true
        }

        // Apply side effects
        switch command {
        // Application Launch
        case let command as RUMApplicationStartCommand:
            let isUserLaunch = context.launchInfo.launchReason == .userLaunch
            let viewStartsAtProcessLaunch = viewStartTime == context.launchInfo.processLaunchDate

            if isUserLaunch && viewStartsAtProcessLaunch {
                // Application start is only reported for user-initiated launches,
                // and only if the "ApplicationLaunch" view starts exactly at process start.
                //
                // In some valid cases, the view may start later (e.g., if RUM.enable() is called
                // while the app is already in ACTIVE state), in which case we don't assume
                // it’s part of the launch sequence.
                //
                // This check ensures the "application_start" action spans a meaningful portion
                // of the app startup (from process start to a point within the launch view).
                // Otherwise, it could be reported as starting "before" the view exists.
                sendApplicationStartAction(on: command, context: context, writer: writer)
            }
            if !isInitialView || viewPath != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL {
                dependencies.telemetry.error(
                    "A RUMApplicationStartCommand got sent to a View other than the ApplicationLaunch view."
                )
            }
            // Application Launch also serves as a StartView command for this view
            didReceiveStartCommand = true
            needsViewUpdate = true

        case let command as RUMHandleAppLifecycleEventCommand:
            if command.event == .didEnterBackground && viewPath == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL {
                // Stop 'ApplicationLaunch' view on transition to background
                isActiveView = false
                needsViewUpdate = true // yes, to update duration
            } else if command.event == .willEnterForeground && viewPath == RUMOffViewEventsHandlingRule.Constants.backgroundViewURL {
                // Stop 'Background' view on transition to foreground
                isActiveView = false
                needsViewUpdate = false // no, to not update the duration
            }

        // Session stop
        case is RUMStopSessionCommand:
            isActiveView = false
            needsViewUpdate = true

        // View commands
        case let command as RUMAddViewAttributesCommand where isActiveView:
            if command.areInternalAttributes {
                internalAttributes.merge(command.attributes) { $1 }
            } else {
                attributes.merge(command.attributes) { $1 }
            }
        case let command as RUMRemoveViewAttributesCommand where isActiveView:
            command.keysToRemove.forEach { attributes.removeValue(forKey: $0) }
        case let command as RUMStartViewCommand where identity == command.identity:
            if didReceiveStartCommand {
                // This is the case of duplicated "start" command. We know that the Session scope has created another instance of
                // the `RUMViewScope` for tracking this View, so we mark this one as inactive.
                isActiveView = false
            }
            attributes.merge(command.attributes) { $1 }
            didReceiveStartCommand = true
            needsViewUpdate = true
        case let command as RUMStartViewCommand where identity != command.identity && isActiveView:
            // This gets effective in case when the user didn't end the view explicitly.
            // If the view is flagged as "active" but another view is started, we know it needs to be
            // deactivated. This is achieved by setting `isActiveView` to `false` and sending one more view update.
            isActiveView = false
            needsViewUpdate = true
            // View attributes are updated with the last snapshot of the global attributes
            attributes = command.globalAttributes.merging(self.attributes) { $1 }
        case let command as RUMStopViewCommand where identity == command.identity:
            isActiveView = false
            needsViewUpdate = true
            // View attributes are updated with the last snapshot of the global attributes
            attributes = command.globalAttributes.merging(self.attributes) { $1 }.merging(command.attributes) { $1 }
        case let command as RUMAddViewLoadingTime where isActiveView:
            attributes.merge(command.attributes) { $1 }
            addViewLoadingTime(on: command)
        case let command as RUMAddViewTimingCommand where isActiveView:
            attributes.merge(command.attributes) { $1 }
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
            } else if let actionScope = userActionScope {
                if command.instrumentation.priority > actionScope.instrumentation.priority {
                    addDiscreteUserAction(on: command)
                } else {
                    reportActionDropped(type: command.actionType, name: command.name)
                }
            } else {
                addDiscreteUserAction(on: command)
            }

        // Error command
        case let command as RUMErrorCommand where isActiveView:
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

        if shouldComplete {
            interactionToNextViewMetric?.trackViewComplete(viewID: viewUUID)
            if let viewHitchesReader {
                viewEndedMetric.track(
                    hitchesTelemetry: viewHitchesReader.telemetryModel,
                    viewDuration: command.time.timeIntervalSince(viewStartTime).toInt64Nanoseconds
                )
                dependencies.renderLoopObserver?.unregister(viewHitchesReader)
            }
            viewEndedMetric.send()
        }

        return !shouldComplete
    }

    private func addViewLoadingTime(on command: RUMAddViewLoadingTime) {
        if viewLoadingTime == nil {
            let time = command.time.timeIntervalSince(viewStartTime)
            viewLoadingTime = time
            needsViewUpdate = true
            DD.logger.debug("View loading time \(time)ns added to the view \(viewName)")
            dependencies.telemetry.send(telemetry: .usage(.init(event: .addViewLoadingTime(.init(noActiveView: false, noView: false, overwritten: false)))))
        } else if command.overwrite {
            let time = command.time.timeIntervalSince(viewStartTime)
            viewLoadingTime = time
            needsViewUpdate = true
            DD.logger.warn("View loading time already exists for the view \(viewName). Replacing the existing \(String(describing: viewLoadingTime))ns with the new \(time)ns loading time.")
            dependencies.telemetry.send(telemetry: .usage(.init(event: .addViewLoadingTime(.init(noActiveView: false, noView: false, overwritten: true)))))
        }
    }

    private func startResource(on command: RUMStartResourceCommand) {
        resourceScopes[command.resourceKey] = RUMResourceScope(
            parent: self,
            dependencies: dependencies,
            resourceKey: command.resourceKey,
            startTime: command.time,
            serverTimeOffset: serverTimeOffset,
            url: command.url,
            httpMethod: command.httpMethod,
            resourceKindBasedOnRequest: command.kind,
            spanContext: command.spanContext,
            networkSettledMetric: networkSettledMetric,
            onResourceEvent: { [weak self] wasSent in
                if wasSent {
                    self?.resourcesCount += 1
                }
                self?.needsViewUpdate = true
            },
            onErrorEvent: { [weak self] wasSent in
                if wasSent {
                    self?.errorsCount += 1
                }
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
            attributes: attributes.merging(command.attributes) { $1 }, // user action events also have view attributes
            startTime: command.time,
            serverTimeOffset: serverTimeOffset,
            isContinuous: true,
            instrumentation: command.instrumentation,
            interactionToNextViewMetric: interactionToNextViewMetric,
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
            attributes: attributes.merging(command.attributes) { $1 }, // user action events also have view attributes
            startTime: command.time,
            serverTimeOffset: serverTimeOffset,
            isContinuous: false,
            instrumentation: command.instrumentation,
            interactionToNextViewMetric: interactionToNextViewMetric,
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
                globalAttributes: command.globalAttributes,
                attributes: attributes.merging(command.attributes) { $1 }, // user action events also have view attributes
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

        // Application start event attributes
        // Attribute Precedence: global attributes <- view attributes (highest priority)
        var commandAttributes = command.globalAttributes
            .merging(attributes) { $1 }

        var loadingTime: Int64?

        if context.launchInfo.launchReason == .prewarming {
            // Set `active_pre_warm` attribute to true in case
            // of pre-warmed app.
            commandAttributes[Constants.activePrewarm] = true
        } else if let launchTime = context.launchInfo.timeToDidBecomeActive {
            // Report Application Launch Time only if not pre-warmed
            loadingTime = launchTime.toInt64Nanoseconds
        } else {
            // The launchTime can be `nil` if the application is not yet
            // active (UIApplicationDidBecomeActiveNotification). That is
            // the case when instrumenting a SwiftUI application that start
            // a RUM view on `SwiftUI.View/onAppear`.
            //
            // In that case, we consider the time between the application
            // launch and the sdkInitialization as the application loading
            // time.
            let launchDate = context.launchInfo.processLaunchDate
            loadingTime = command.time.timeIntervalSince(launchDate).toInt64Nanoseconds
        }

        let actionEvent = RUMActionEvent(
            dd: .init(
                action: nil,
                browserSdkVersion: nil,
                configuration: .init(sessionReplaySampleRate: nil, sessionSampleRate: Double(dependencies.sessionSampler.samplingRate)),
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: self.context.sessionPrecondition
                )
            ),
            account: .init(context: context),
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
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            container: nil,
            context: .init(contextInfo: commandAttributes),
            date: viewStartTime.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: context.normalizedDevice(),
            display: nil,
            os: context.os,
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
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

        if let hasContextReplay = context.hasReplay {
            hasReplay = hasReplay || hasContextReplay
        }

        let attributes: [AttributeKey: AttributeValue]
        if isActiveView {
            // View event attributes
            // Attribute Precedence: global attributes <- view attributes (highest priority)
            attributes = command.globalAttributes.merging(self.attributes) { $1 }
        } else {
            // This view is not active. The attributes should not be changed.
            attributes = self.attributes
        }

        let errorCommand = command as? RUMErrorCommand
        let isCrash = errorCommand?.isCrash ?? false
        let completionHandler = errorCommand?.completionHandler ?? NOPCompletionHandler

        // RUMM-1779 Keep view active as long as we have ongoing resources
        let isActive = isActiveView || !resourceScopes.isEmpty
        // RUMM-2079 `time_spent` can't be lower than 1ns
        let timeSpent = max(Constants.minimumTimeSpent, command.time.timeIntervalSince(viewStartTime))
        let cpuInfo = vitalInfoSampler?.cpu
        let memoryInfo = vitalInfoSampler?.memory
        let refreshRateInfo = vitalInfoSampler?.refreshRate
        let isSlowRendered = refreshRateInfo?.meanValue.map { $0 < Constants.slowRenderingThresholdFPS }
        let networkSettledTime = networkSettledMetric.value(with: context.applicationStateHistory)
        var interactionToNextViewTime = interactionToNextViewMetric?.value(for: viewUUID) ?? .failure(.disabled)
        var slowFramesRate: Double?
        var freezeRate: Double?
        if let command = command as? RUMStopViewCommand,
           command.identity == identity,
           timeSpent >= Constants.minimumTimeSpentForRates {
            if let totalHitchesDuration = viewHitchesReader?.dataModel.hitchesDuration {
                slowFramesRate = totalHitchesDuration / timeSpent * Double(1.toMilliseconds) // milliseconds/second
            }
            if dependencies.hasAppHangsEnabled {
                freezeRate = totalAppHangDuration / timeSpent * 1.hours // seconds/hour
            }
        }
        // Only overwrite with a custom value if INV was disabled
        if interactionToNextViewTime == .failure(.disabled),
           let customInvValue = internalAttributes[CrossPlatformAttributes.customINVValue] as? (any BinaryInteger),
           let customInvValue = Int64(exactly: customInvValue) {
            interactionToNextViewTime = .success(TimeInterval(fromNanoseconds: customInvValue))
        }

        // Only add the performance member if we have a value for it
        let performance: RUMViewEvent.View.Performance?
        if let fbcMetric = internalAttributes[CrossPlatformAttributes.flutterFirstBuildComplete] as? (any BinaryInteger),
           let fbcMetric = Int64(exactly: fbcMetric) {
            performance = .init(
                cls: nil,
                fbc: .init(timestamp: fbcMetric),
                fcp: nil,
                fid: nil,
                inp: nil
            )
        } else {
            performance = nil
        }

        var localAttributes = attributes

        if let accessibility = self.accessibilityReader?.state {
            localAttributes["accessibility"] = accessibility
        }

        let viewEvent = RUMViewEvent(
            dd: .init(
                browserSdkVersion: nil,
                cls: nil,
                configuration: .init(
                    sessionReplaySampleRate: nil,
                    sessionSampleRate: Double(dependencies.sessionSampler.samplingRate),
                    startSessionReplayRecordingManually: nil
                ),
                documentVersion: version.toInt64,
                pageStates: nil,
                replayStats: .init(
                    recordsCount: context.recordsCountByViewID[viewUUID.toRUMDataFormat],
                    segmentsCount: nil,
                    segmentsTotalRawSize: nil
                ),
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: self.context.sessionPrecondition
                )
            ),
            account: .init(context: context),
            application: .init(currentLocale: context.localeInfo.currentLocale, id: self.context.rumApplicationID),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            container: nil,
            context: .init(contextInfo: localAttributes),
            date: viewStartTime.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: context.normalizedDevice(),
            display: nil,
            featureFlags: .init(featureFlagsInfo: featureFlags),
            os: context.os,
            privacy: nil,
            service: context.service,
            session: .init(
                hasReplay: hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                isActive: self.context.isSessionActive,
                sampledForReplay: nil,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
            usr: .init(context: context),
            version: context.version,
            view: .init(
                action: .init(count: actionsCount.toInt64),
                cpuTicksCount: cpuInfo?.greatestDiff,
                cpuTicksPerSecond: timeSpent > 1.0 ? cpuInfo?.greatestDiff?.divideIfNotZero(by: Double(timeSpent)) : nil,
                crash: isCrash ? .init(count: 1) : .init(count: 0),
                cumulativeLayoutShift: nil,
                cumulativeLayoutShiftTargetSelector: nil,
                cumulativeLayoutShiftTime: nil,
                customTimings: .init(customTimingsInfo: customTimings.reduce(into: [:]) { acc, element in
                    acc[sanitizeCustomTimingName(customTiming: element.key)] = element.value
                }),
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
                freezeRate: freezeRate,
                frozenFrame: .init(count: frozenFramesCount),
                frustration: .init(count: frustrationCount),
                id: viewUUID.toRUMDataFormat,
                inForegroundPeriods: nil,
                interactionToNextPaint: nil,
                interactionToNextPaintTargetSelector: nil,
                interactionToNextPaintTime: nil,
                interactionToNextViewTime: interactionToNextViewTime.value?.toInt64Nanoseconds,
                isActive: isActive,
                isSlowRendered: isSlowRendered ?? false,
                jsRefreshRate: viewPerformanceMetrics[.jsFrameTimeSeconds]?.asJsRefreshRate(),
                largestContentfulPaint: nil,
                largestContentfulPaintTargetSelector: nil,
                loadEvent: nil,
                loadingTime: viewLoadingTime?.toInt64Nanoseconds,
                loadingType: nil,
                longTask: .init(count: longTasksCount),
                memoryAverage: memoryInfo?.meanValue,
                memoryMax: memoryInfo?.maxValue,
                name: viewName,
                networkSettledTime: networkSettledTime.value?.toInt64Nanoseconds,
                performance: performance,
                referrer: nil,
                refreshRateAverage: refreshRateInfo?.meanValue,
                refreshRateMin: refreshRateInfo?.minValue,
                resource: .init(count: resourcesCount.toInt64),
                slowFrames: viewHitchesReader?.dataModel.hitches.map { .init(duration: $0.duration, start: $0.start) },
                slowFramesRate: slowFramesRate,
                timeSpent: timeSpent.toInt64Nanoseconds,
                url: viewPath
            )
        )

        if let event = dependencies.eventBuilder.build(from: viewEvent) {
            writer.write(
                value: event,
                metadata: event.metadata(viewIndexInSession: viewIndexInSession),
                completion: completionHandler
            )

            // Update fatal error context with recent RUM view:
            dependencies.fatalErrorContext.view = event

            // Track this view in Session Ended metric:
            var instrumentationType: InstrumentationType?
            if let command = command as? RUMStartViewCommand, command.identity == identity {
                instrumentationType = command.instrumentationType
            }
            dependencies.sessionEndedMetric.track(
                view: event,
                instrumentationType: instrumentationType,
                in: self.context.sessionID
            )

            // Track this event in View Ended metric:
            viewEndedMetric.track(viewEvent: event, instrumentationType: instrumentationType)
            viewEndedMetric.track(networkSettledResult: networkSettledTime)
            viewEndedMetric.track(interactionToNextViewResult: interactionToNextViewTime)

            // Update the state of the view in watchdog termination monitor
            // if a watchdog termination occurs in this session, in the next session
            // a watchdog termination event will be sent using saved view event.
            dependencies.watchdogTermination?.update(viewEvent: event)
        } else { // if event was dropped by mapper
            version -= 1
            completionHandler()
        }
    }

    private func sendErrorEvent(on command: RUMErrorCommand, context: DatadogContext, writer: Writer) {
        errorsCount += 1
        totalAppHangDuration += (command as? RUMAddCurrentViewAppHangCommand)?.hangDuration ?? 0
        if let command = (command as? RUMAddCurrentViewAppHangCommand) {
            self.hangs.append((command.time.timeIntervalSince(viewStartTime), command.hangDuration))
        }

        // Error event attributes
        // Attribute Precedence: global attributes <- view attributes <- event attributes (highest priority)
        var commandAttributes = command.globalAttributes
            .merging(attributes) { $1 }
            .merging(command.attributes) { $1 }
        let errorFingerprint: String? = commandAttributes.removeValue(forKey: RUM.Attributes.errorFingerprint)?.dd.decode()
        let timeSinceAppStart = command.time.timeIntervalSince(context.launchInfo.processLaunchDate).toInt64Milliseconds

        var binaryImages = command.binaryImages?.compactMap { $0.toRUMDataFormat }
        if commandAttributes.removeValue(forKey: CrossPlatformAttributes.includeBinaryImages)?.dd.decode() == true {
            // Don't try to get binary images if we already have them.
            if binaryImages == nil {
                // TODO: RUM-4072 Replace full backtrace reporter with simpler binary image fetcher
                binaryImages = try? dependencies.backtraceReporter?.generateBacktrace()?.binaryImages.compactMap { $0.toRUMDataFormat }
            }
        }

        let errorEvent = RUMErrorEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .init(sessionReplaySampleRate: nil, sessionSampleRate: Double(dependencies.sessionSampler.samplingRate)),
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: self.context.sessionPrecondition
                )
            ),
            account: .init(context: context),
            action: self.context.activeUserActionID.map { rumUUID in
                .init(id: .string(value: rumUUID.toRUMDataFormat))
            },
            application: .init(id: self.context.rumApplicationID),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            container: nil,
            context: .init(contextInfo: commandAttributes),
            date: command.time.addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: context.normalizedDevice(),
            display: nil,
            error: .init(
                binaryImages: binaryImages,
                category: command.category,
                causes: nil,
                csp: nil,
                fingerprint: errorFingerprint,
                handling: nil,
                handlingStack: nil,
                id: nil,
                isCrash: command.isCrash ?? false,
                message: command.message,
                meta: nil,
                resource: nil,
                source: command.source.toRUMDataFormat,
                sourceType: command.errorSourceType,
                stack: command.stack,
                threads: command.threads?.compactMap { $0.toRUMDataFormat },
                timeSinceAppStart: timeSinceAppStart,
                type: command.type,
                wasTruncated: command.isStackTraceTruncated
            ),
            featureFlags: .init(featureFlagsInfo: featureFlags),
            freeze: (command as? RUMAddCurrentViewAppHangCommand).map { appHangCommand in
                .init(duration: appHangCommand.hangDuration.toInt64Nanoseconds)
            },
            os: context.os,
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
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
            // Call the completion when the event is discarded.
            // When the error is kept, the completion is called when the
            // view update is written.
            command.completionHandler()
        }
    }

    private func sendLongTaskEvent(on command: RUMAddLongTaskCommand, context: DatadogContext, writer: Writer) {
        let taskDurationInNs = command.duration.toInt64Nanoseconds
        let isFrozenFrame = taskDurationInNs > Constants.frozenFrameThresholdInNs

        // Long task event attributes
        // Attribute Precedence: global attributes <- view attributes <- event attributes (highest priority)
        let commandAttributes = command.globalAttributes
            .merging(attributes) { $1 }
            .merging(command.attributes) { $1 }

        let longTaskEvent = RUMLongTaskEvent(
            dd: .init(
                browserSdkVersion: nil,
                configuration: .init(sessionReplaySampleRate: nil, sessionSampleRate: Double(dependencies.sessionSampler.samplingRate)),
                discarded: nil,
                session: .init(
                    plan: .plan1,
                    sessionPrecondition: self.context.sessionPrecondition
                )
            ),
            account: .init(context: context),
            action: self.context.activeUserActionID.map {
                .init(id: .string(value: $0.toRUMDataFormat))
            },
            application: .init(id: self.context.rumApplicationID),
            buildId: context.buildId,
            buildVersion: context.buildNumber,
            ciTest: dependencies.ciTest,
            connectivity: .init(context: context),
            container: nil,
            context: .init(contextInfo: commandAttributes),
            date: (command.time - command.duration).addingTimeInterval(serverTimeOffset).timeIntervalSince1970.toInt64Milliseconds,
            device: context.normalizedDevice(),
            display: nil,
            longTask: .init(
                blockingDuration: nil,
                duration: taskDurationInNs,
                entryType: nil,
                firstUiEventTimestamp: nil,
                id: nil,
                isFrozenFrame: isFrozenFrame,
                renderStart: nil,
                scripts: nil,
                startTime: nil,
                styleAndLayoutStart: nil
            ),
            os: context.os,
            service: context.service,
            session: .init(
                hasReplay: context.hasReplay,
                id: self.context.sessionID.toRUMDataFormat,
                type: dependencies.sessionType
            ),
            source: .init(rawValue: context.source) ?? .ios,
            synthetics: dependencies.syntheticsTest,
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

private extension Result {
    var value: Success? {
        switch self {
        case .success(let success): return success
        case .failure: return nil
        }
    }
}
