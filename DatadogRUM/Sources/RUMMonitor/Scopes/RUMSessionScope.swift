/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import DatadogInternal

internal class RUMSessionScope: RUMScope, RUMContextProvider {
    struct Constants {
        /// If no interaction is registered within this period, a new session is started.
        static let sessionTimeoutDuration: TimeInterval = 15 * 60 // 15 minutes
        /// Maximum duration of a session. If it gets exceeded, a new session is started.
        static let sessionMaxDuration: TimeInterval = 4 * 60 * 60 // 4 hours
    }

    /// Whether a session is timed out due to inactivity, given the time of its last interaction.
    static func hasTimedOut(lastInteractionTime: Date, currentTime: Date) -> Bool {
        currentTime.timeIntervalSince(lastInteractionTime) >= Constants.sessionTimeoutDuration
    }

    /// Whether a session has exceeded its maximum duration, given its start time.
    static func hasExpired(sessionStartTime: Date, currentTime: Date) -> Bool {
        currentTime.timeIntervalSince(sessionStartTime) >= Constants.sessionMaxDuration
    }

    /// The reason of ending a session.
    enum EndReason: String {
        /// The session timed out because it received no interaction for x minutes.
        /// See: ``Constants.sessionTimeoutDuration``.
        case timeOut
        /// The session expired because it exceeded max duration.
        /// See: ``Constants.sessionMaxDuration``.
        case maxDuration
        /// The session was ended manually with ``RUMMonitorProtocol.stopSession()`` API.
        case stopAPI
    }

    // MARK: - Child Scopes

    /// Active View scopes. Scopes are added / removed when the View starts / stops displaying.
    private(set) var viewScopes: [RUMViewScope] = [] {
        didSet {
            updateRepresentativeView()
            if !state.hasTrackedAnyView && !viewScopes.isEmpty {
                state = RUMSessionState(
                    sessionUUID: state.sessionUUID,
                    isSampled: state.isSampled,
                    isInitialSession: state.isInitialSession,
                    hasTrackedAnyView: true,
                    didStartWithReplay: state.didStartWithReplay
                )
            }
        }
    }

    /// Views restored at a session boundary that still need an initial event.
    /// The triggering command initializes its own target through normal routing;
    /// unaffected scene branches are initialized explicitly afterward.
    private var restoredViewsAwaitingInitialEvent: [RUMViewScope] = []

    /// Representative active view used for legacy, process-wide context consumers.
    /// Scene-targeted commands are routed independently and update this selection
    /// when they represent a user interaction.
    private(set) var activeView: RUMViewScope?

    /// Scene that most recently produced a targeted user interaction.
    private var representativeSceneIdentifier: RUMSceneIdentifier?

    /// If there is an active view.
    private var hasActiveView: Bool { activeView != nil }

    /// Information about the application state since `RUM.enable()` was called.
    private let applicationState: RUMApplicationState
    /// Feature Operation manager for processing Feature Operation commands.
    private lazy var featureOperationManager: RUMFeatureOperationManager = {
        RUMFeatureOperationManager(parent: self, dependencies: dependencies, sessionSampler: sampler)
    }()
    /// App launch manager to process TTID and TTFD commands.
    private lazy var appLaunchManager: RUMAppLaunchManager = {
        RUMAppLaunchManager(
            parent: self,
            dependencies: dependencies,
            telemetryController: AppLaunchMetricController(telemetry: dependencies.telemetry)
        )
    }()

    /// Information about this session state, shared with `CrashContext`.
    private var state: RUMSessionState {
        didSet {
            dependencies.fatalErrorContext.sessionState = state
        }
    }

    // MARK: - Initialization

    unowned let parent: RUMContextProvider

    /// Container bundling dependencies for this scope.
    let dependencies: RUMScopeDependencies

    /// Automatically detect background events by creating "Background" view if no other view is active
    let trackBackgroundEvents: Bool

    /// This Session UUID.
    let sessionUUID: RUMUUID
    /// The precondition that led to the creation of this session.
    /// TODO: RUM-1650 This should become non-optional after all preconditions are implemented.
    let startPrecondition: RUMSessionPrecondition?
    /// The deterministic sampler for this session, seeded from the session UUID.
    let sampler: DeterministicSampler
    /// If the session is currently active. Set to `false` upon reaching the `EndReason`.
    var isActive: Bool { endReason == nil }
    /// If this is the very first session created in the current app process (`false` for session created upon expiration of a previous one).
    let isInitialSession: Bool
    /// The start time of this Session, measured in device date. In initial session this is the time of SDK init.
    let sessionStartTime: Date
    /// Time of the last RUM interaction noticed by this Session.
    private(set) var lastInteractionTime: Date
    /// Indicates whether the "ApplicationLaunch" view was active when the app entered the background.
    private var hadApplicationLaunchViewWhenEnteringBackground: Bool? = nil
    /// The reason why this session has ended or `nil` if it is still active.
    private(set) var endReason: EndReason? {
        didSet {
            guard oldValue == nil, endReason != nil else {
                return
            }

            dependencies.timeseriesCollector?.stop(sessionID: sessionUUID.toRUMDataFormat)

            // Session timeout and max-duration checks happen before commands are
            // propagated to view scopes. Explicitly release their cache pins so
            // a non-transferred view cannot survive forever or become a stale
            // WebView container. A refreshed session will insert and pin its own
            // replacement view IDs when transfer is enabled.
            viewScopes.lazy.filter(\.isActiveView).forEach {
                dependencies.viewCache.markInactive(id: $0.viewUUID.toRUMDataFormat)
            }
        }
    }

    /// Counter to track the index of views in this session. Starts at 0 for the first view.
    private var nextViewIndex: Int = 0

    /// Legacy process-wide INV tracker used when no scene can be resolved.
    private let processInteractionToNextViewMetric: INVMetricTracking?
    /// Independent INV history per scene prevents navigation in one window from
    /// treating another window's view as its predecessor.
    private var interactionToNextViewMetricsByScene: [RUMSceneIdentifier: INVMetricTracking] = [:]

    init(
        isInitialSession: Bool,
        parent: RUMContextProvider,
        startTime: Date,
        startPrecondition: RUMSessionPrecondition?,
        context: DatadogContext,
        dependencies: RUMScopeDependencies,
        applicationState: RUMApplicationState,
        resumingViewScope: RUMViewScope? = nil,
        resumingViewScopes: [RUMViewScope] = []
    ) {
        let sessionUUID = dependencies.rumUUIDGenerator.generateUnique()

        self.parent = parent
        self.dependencies = dependencies
        self.applicationState = applicationState
        self.sampler = DeterministicSampler(
            uuid: sessionUUID.rawValue,
            samplingRate: dependencies.samplingRate
        )
        self.startPrecondition = startPrecondition
        self.sessionUUID = sessionUUID
        self.isInitialSession = isInitialSession
        self.sessionStartTime = startTime
        self.lastInteractionTime = startTime
        self.trackBackgroundEvents = dependencies.trackBackgroundEvents
        self.endReason = nil
        self.state = RUMSessionState(
            sessionUUID: sessionUUID.rawValue,
            isSampled: sampler.isSampled,
            isInitialSession: isInitialSession,
            hasTrackedAnyView: false,
            didStartWithReplay: context.hasReplay
        )
        self.processInteractionToNextViewMetric = dependencies.interactionToNextViewMetricFactory()

        if sampler.isSampled {
            // Start tracking "RUM Session Ended" metric for this session
            dependencies.sessionEndedMetric.startMetric(
                sessionID: sessionUUID,
                precondition: startPrecondition,
                context: context
            )
        }

        var viewsToResume = resumingViewScopes
        if let resumingViewScope,
           !viewsToResume.contains(where: {
               $0.identity == resumingViewScope.identity
                   && $0.sceneIdentifier == resumingViewScope.sceneIdentifier
           }) {
            viewsToResume.append(resumingViewScope)
        }

        for viewScope in viewsToResume {
            startView(
                isInitialView: false,
                dependencies: dependencies,
                identity: viewScope.identity,
                path: viewScope.viewPath,
                name: viewScope.viewName,
                customTimings: [:],
                startTime: startTime,
                serverTimeOffset: viewScope.serverTimeOffset,
                hasReplay: context.hasReplay,
                sceneIdentifier: viewScope.sceneIdentifier,
                didReceiveStartCommand: true
            )
            if let restoredView = viewScopes.last {
                restoredViewsAwaitingInitialEvent.append(restoredView)
            }
        }

        // Update fatal error context with recent RUM session state:
        dependencies.fatalErrorContext.sessionState = state

        if sampler.isSampled {
            dependencies.timeseriesCollector?.start(
                sessionID: sessionUUID.toRUMDataFormat,
                applicationID: dependencies.rumApplicationID,
                sessionType: dependencies.sessionType
            )
            if !context.applicationStateHistory.currentState.isRunningInForeground {
                dependencies.timeseriesCollector?.pause(sessionID: sessionUUID.toRUMDataFormat)
            }
        }
    }

    /// Creates a new Session upon expiration of the previous one.
    convenience init(
        from expiredSession: RUMSessionScope,
        startTime: Date,
        startPrecondition: RUMSessionPrecondition?,
        context: DatadogContext,
        transferActiveView: Bool,
        applicationState: RUMApplicationState,
        resumingViewScopes: [RUMViewScope]? = nil
    ) {
        self.init(
            // If the expired session was marked as "initial" but didn’t track any views, mark this new session as the new "initial".
            isInitialSession: expiredSession.state.isInitialSession && !expiredSession.state.hasTrackedAnyView,
            parent: expiredSession.parent,
            startTime: startTime,
            startPrecondition: startPrecondition,
            context: context,
            dependencies: expiredSession.dependencies,
            applicationState: applicationState
        )

        // Transfer every concurrently active View to the refreshed session.
        if transferActiveView {
            var activeViews = resumingViewScopes ?? expiredSession.viewScopes.filter(\.isActiveView)
            if let representative = expiredSession.activeView,
               let index = activeViews.firstIndex(where: { $0 === representative }) {
                activeViews.append(activeViews.remove(at: index))
            }

            representativeSceneIdentifier = expiredSession.representativeSceneIdentifier
            for lastActiveView in activeViews {
                startView(
                    isInitialView: false,
                    dependencies: dependencies,
                    identity: lastActiveView.identity,
                    path: lastActiveView.viewPath,
                    name: lastActiveView.viewName,
                    customTimings: lastActiveView.customTimings,
                    startTime: startTime,
                    serverTimeOffset: context.serverTimeOffset,
                    hasReplay: context.hasReplay,
                    sceneIdentifier: lastActiveView.sceneIdentifier,
                    didReceiveStartCommand: true
                )
                if let restoredView = viewScopes.last {
                    restoredViewsAwaitingInitialEvent.append(restoredView)
                }
            }
            updateRepresentativeView()
        }
    }

    // MARK: - RUMContextProvider

    var context: RUMContext {
        var context = parent.context
        context.sessionID = sessionUUID
        context.activeViewID = activeView?.viewUUID
        context.activeViewName = activeView?.viewName
        context.isSessionActive = isActive
        context.sessionPrecondition = startPrecondition
        return context
    }

    var attributes: [AttributeKey: AttributeValue] { [:] }

    // MARK: - RUMScope

    func process(command incomingCommand: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        var command = incomingCommand

        if hasTimedOut(currentTime: command.time) {
            endReason = .timeOut
            return false // end this session (no longer keep the session scope)
        }
        if hasExpired(currentTime: command.time) {
            endReason = .maxDuration
            return false // end this session (no longer keep the session scope)
        }

        // A source-less manual start retains legacy representative semantics, but
        // joins that representative's scene branch instead of creating a third,
        // process-global branch alongside scene-backed views.
        if var startViewCommand = command as? RUMStartViewCommand,
           startViewCommand.target == .processRepresentative,
           let sceneIdentifier = activeView?.sceneIdentifier {
            startViewCommand.target = .scene(sceneIdentifier)
            command = startViewCommand
        }

        // An explicit action target is authoritative only when it
        // resolves to a live view. Preserve the independently inferred target
        // when a scene has already closed or has not started a RUM view yet.
        if var actionCommand = command as? RUMUserActionCommand,
           let explicitTarget = actionCommand.explicitTarget,
           actionTargetView(for: explicitTarget, command: actionCommand) != nil {
            actionCommand.target = explicitTarget
            command = actionCommand
        }

        if command.isUserInteraction {
            lastInteractionTime = command.time
            let interactedSceneIdentifier: RUMSceneIdentifier?
            switch command.target {
            case .scene(let sceneIdentifier):
                interactedSceneIdentifier = sceneIdentifier
            case .view(let viewID):
                interactedSceneIdentifier = viewScopes.first(where: {
                    $0.viewUUID == viewID
                })?.sceneIdentifier ?? dependencies.viewCache.sceneIdentifier(
                    forViewID: viewID.toRUMDataFormat
                )
            case .none, .processRepresentative, .allActiveViews:
                interactedSceneIdentifier = nil
            }
            if let interactedSceneIdentifier,
               !(command is RUMStartViewCommand) {
                representativeSceneIdentifier = interactedSceneIdentifier
                updateRepresentativeView()
            }
        }

        if !sampler.isSampled {
            // Make sure sessions end even if they are not sampled
            if command is RUMStopSessionCommand {
                endReason = .stopAPI
                return false // end this session (no longer keep the session scope)
            }

            return true // keep this session until it gets ended by any `endReason`
        }

        // Action commands must reach their recipient before expiration so an
        // overdue stop can contribute its attributes. Peers advance time during
        // routing below. Other commands keep their existing expiration ordering.
        if !(command is RUMUserActionCommand) {
            viewScopes.forEach {
                $0.expireUserActionIfNeeded(on: command, context: context, writer: writer)
            }
        }

        var deactivating = false
        if isActive {
            switch command {
            case _ as RUMStopSessionCommand:
                dependencies.sessionEndedMetric.trackWasStopped(sessionID: self.context.sessionID)
                endReason = .stopAPI
                deactivating = true

            case let startApplicationCommand as RUMApplicationStartCommand:
                startApplicationLaunchView(on: startApplicationCommand, context: context, writer: writer)

            case let startViewCommand as RUMStartViewCommand:
                // Start view scope explicitly on receiving "start view" command
                startView(on: startViewCommand, context: context)
                appLaunchManager.process(command, context: context, writer: writer)
            case let appLifecycleCommand as RUMHandleAppLifecycleEventCommand where appLifecycleCommand.event == .didEnterBackground:
                hadApplicationLaunchViewWhenEnteringBackground = activeView?.viewPath == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL
                appLaunchManager.process(command, context: context, writer: writer)
                dependencies.timeseriesCollector?.pause(sessionID: sessionUUID.toRUMDataFormat)
            case let appLifecycleCommand as RUMHandleAppLifecycleEventCommand where appLifecycleCommand.event == .willEnterForeground:
                if hadApplicationLaunchViewWhenEnteringBackground == true {
                    startApplicationLaunchView(on: appLifecycleCommand, context: context, writer: writer)
                }
                hadApplicationLaunchViewWhenEnteringBackground = nil
                dependencies.timeseriesCollector?.resume(sessionID: sessionUUID.toRUMDataFormat)

            case var operationStepVitalCommand as RUMOperationStepVitalCommand:
                // Forward command to the feature operation manager
                let operationTarget = resolveOperationTarget(
                    for: operationStepVitalCommand
                )
                operationStepVitalCommand.target = operationTarget.target
                let operationView = featureOperationManager.process(
                    operationStepVitalCommand,
                    context: context,
                    writer: writer,
                    activeView: operationTarget.view,
                    activeViews: viewScopes,
                    processRepresentativeView: activeView
                )
                if let operationView {
                    operationStepVitalCommand.target = .view(operationView.viewUUID)
                    propagate(command: operationStepVitalCommand, context: context, writer: writer)
                }
                emitInitialEventsForRestoredViews(on: command, context: context, writer: writer)
                return isActive || !viewScopes.isEmpty
            case let command as RUMTimeToInitialDisplayCommand:
                appLaunchManager.process(command, context: context, writer: writer, activeView: activeView)
                dependencies.renderLoopObserver?.unregister(dependencies.firstFrameReader)
                emitInitialEventsForRestoredViews(on: command, context: context, writer: writer)
                // command doesn't need to be propagated to other scopes
                return true
            case let command as RUMTimeToFullDisplayCommand:
                appLaunchManager.process(command, context: context, writer: writer, activeView: activeView)
                emitInitialEventsForRestoredViews(on: command, context: context, writer: writer)
                // command doesn't need to be propagated to other scopes
                return true
            default:
                if shouldHandleOffViewCommand(command) {
                    handleOffViewCommand(command: command, context: context, writer: writer)
                }
            }
        }

        // Propagate only to the selected scene branch. Process-wide commands keep
        // one representative branch so enabling concurrent views cannot duplicate
        // resources, actions, errors, or other unscoped events.
        propagate(command: command, context: context, writer: writer)
        emitInitialEventsForRestoredViews(on: command, context: context, writer: writer)

        if (isActive || deactivating) && !hasActiveView {
            // If this session is active and there is no active view, update fatal error context accordingly, so eventual
            // error won't be associated to an inactive view and instead we will consider starting background view to track it.
            // We also want to send this as a session is being stopped.
            // It means that with Background Events Tracking disabled, eventual off-view crashes will be dropped
            // similar to how we drop other events.
            dependencies.fatalErrorContext.view = nil
        }

        if let command = command as? RUMAddViewLoadingTime {
            if viewScopes.isEmpty {
                DD.logger.warn("No view found to add the loading time.")
                dependencies.telemetry.usage(event: .addViewLoadingTime(.init(noActiveView: false, noView: true, overwritten: command.overwrite)))
            } else if !hasActiveView {
                DD.logger.warn("No active view found to add the loading time.")
                dependencies.telemetry.usage(event: .addViewLoadingTime(.init(noActiveView: true, noView: false, overwritten: command.overwrite)))
            }
        }

        return isActive || !viewScopes.isEmpty
    }

    // MARK: - RUMCommands Processing

    private func startView(on command: RUMStartViewCommand, context: DatadogContext) {
        let isStartingInitialView = isInitialSession && !state.hasTrackedAnyView
        let sceneIdentifier: RUMSceneIdentifier?
        if case .scene(let identifier) = command.target {
            sceneIdentifier = identifier
            representativeSceneIdentifier = identifier
        } else {
            sceneIdentifier = nil
        }
        startView(
            isInitialView: isStartingInitialView,
            dependencies: dependencies,
            identity: command.identity,
            path: command.path,
            name: command.name,
            customTimings: [:],
            startTime: command.time,
            serverTimeOffset: context.serverTimeOffset,
            hasReplay: context.hasReplay,
            sceneIdentifier: sceneIdentifier
        )
    }

    private func startView(
        isInitialView: Bool,
        dependencies: RUMScopeDependencies,
        identity: ViewIdentifier,
        path: String,
        name: String,
        customTimings: [String: Int64],
        startTime: Date,
        serverTimeOffset: TimeInterval,
        hasReplay: Bool?,
        sceneIdentifier: RUMSceneIdentifier? = nil,
        didReceiveStartCommand: Bool = false
    ) {
        let scope = RUMViewScope(
            isInitialView: isInitialView,
            parent: self,
            dependencies: dependencies,
            identity: identity,
            path: path,
            name: name,
            customTimings: customTimings,
            startTime: startTime,
            serverTimeOffset: serverTimeOffset,
            interactionToNextViewMetric: interactionToNextViewMetric(for: sceneIdentifier),
            viewIndexInSession: nextViewIndex,
            sceneIdentifier: sceneIdentifier,
            didReceiveStartCommand: didReceiveStartCommand
        )
        nextViewIndex += 1

        if path != RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL {
            applicationState.numberOfNonApplicationLaunchViewsCreated += 1
        }

        viewScopes.append(scope)

        let id = scope.viewUUID.toRUMDataFormat

        // Cache the view id at each view start
        dependencies.viewCache.insert(
            id: id,
            timestamp: startTime.timeIntervalSince1970.dd.toInt64Milliseconds,
            hasReplay: hasReplay,
            sceneIdentifier: sceneIdentifier
        )
    }

    private func startApplicationLaunchView(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        let isActivePrewarm = context.launchInfo.launchReason == .prewarming
        let startTime: Date

        if command is RUMApplicationStartCommand {
            if context.applicationStateHistory.initialState == .active {
                // The SDK was initialized after the app became active, not during
                // `application(_:didFinishLaunchingWithOptions:)`. This can happen
                // with lazy initialization from already presented view, or if the SDK
                // was stopped and later re-initialized during runtime.
                startTime = sessionStartTime
            } else {
                // For prewarmed apps, use session start time; otherwise, use launch time.
                //
                // RUM-8372: In practice, `isActivePrewarm == true` is never reached here because
                // prewarmed apps start in the BACKGROUND state, and the ApplicationLaunch view is never created in that case.
                startTime = isActivePrewarm ? sessionStartTime : context.launchInfo.processLaunchDate
            }
        } else {
            // Lazily starting the ApplicationLaunch view to capture events that would
            // otherwise be lost due to the absence of an active view.
            startTime = command.time
        }

        startView(
            isInitialView: true,
            dependencies: dependencies,
            identity: ViewIdentifier(RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL),
            path: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL,
            name: RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewName,
            customTimings: [:],
            startTime: startTime,
            serverTimeOffset: context.serverTimeOffset,
            hasReplay: context.hasReplay,
            sceneIdentifier: command.target.sceneIdentifier
        )
    }

    private func handleOffViewCommand(command: RUMCommand, context: DatadogContext, writer: Writer) {
        let handlingRule = RUMOffViewEventsHandlingRule(
            applicationState: applicationState,
            sessionState: state,
            isAppInForeground: context.applicationStateHistory.currentState.isRunningInForeground,
            isBETEnabled: trackBackgroundEvents,
            command: command
        )

        switch handlingRule {
        case .handleInBackgroundView where command.canStartBackgroundView:
            startBackgroundView(on: command, context: context)
        case .handleInApplicationLaunchView where command.canStartApplicationLaunchView:
            startApplicationLaunchView(on: command, context: context, writer: writer)
        default:
            if let missedEventType = command.missedEventType {
                // In case there was an event missed due to no active view, track it in Session Ended metric
                dependencies.sessionEndedMetric.track(missedEventType: missedEventType, in: sessionUUID)
            }

            if !(isSilentOffViewCommand(command: command)) {
                // As no view scope will handle this command, warn the user on dropping it.
                DD.logger.warn(
                """
                \(String(describing: command)) was detected, but no view is active. To track views automatically, configure
                `RUM.Configuration.uiKitViewsPredicate` or use `.trackRUMView()` modifier in SwiftUI. You can also track views manually
                with `RUMMonitor.shared().startView()` and `RUMMonitor.shared().stopView()`.
                """
                )
            }
        }
    }

    private func isSilentOffViewCommand(command: RUMCommand) -> Bool {
        // It is expected to receive 'keep alive' while no active view (when tracking WebView events), and performance metric
        // updates are sent automatically by cross platform frameworks whether a view is active or not, resulting in log
        // spam.
        return command is RUMKeepSessionAliveCommand || command is RUMUpdatePerformanceMetric || command is RUMHandleAppLifecycleEventCommand
    }

    private func startBackgroundView(on command: RUMCommand, context: DatadogContext) {
        let isStartingInitialView = isInitialSession && !state.hasTrackedAnyView

        startView(
            isInitialView: isStartingInitialView,
            dependencies: dependencies,
            identity: ViewIdentifier(RUMOffViewEventsHandlingRule.Constants.backgroundViewURL),
            path: RUMOffViewEventsHandlingRule.Constants.backgroundViewURL,
            name: RUMOffViewEventsHandlingRule.Constants.backgroundViewName,
            customTimings: [:],
            startTime: command.time,
            serverTimeOffset: context.serverTimeOffset,
            hasReplay: context.hasReplay,
            sceneIdentifier: command.target.sceneIdentifier
        )
    }

    private func hasTimedOut(currentTime: Date) -> Bool {
        Self.hasTimedOut(lastInteractionTime: lastInteractionTime, currentTime: currentTime)
    }

    private func hasExpired(currentTime: Date) -> Bool {
        Self.hasExpired(sessionStartTime: sessionStartTime, currentTime: currentTime)
    }

    private func interactionToNextViewMetric(
        for sceneIdentifier: RUMSceneIdentifier?
    ) -> INVMetricTracking? {
        guard let sceneIdentifier else {
            return processInteractionToNextViewMetric
        }
        if let metric = interactionToNextViewMetricsByScene[sceneIdentifier] {
            return metric
        }
        guard let metric = dependencies.interactionToNextViewMetricFactory() else {
            return nil
        }
        interactionToNextViewMetricsByScene[sceneIdentifier] = metric
        return metric
    }

    private func updateRepresentativeView() {
        let previousRepresentative = activeView

        if let representativeSceneIdentifier,
           let sceneView = viewScopes.last(where: {
               $0.isActiveView && $0.sceneIdentifier == representativeSceneIdentifier
           }) {
            activeView = sceneView
        } else {
            activeView = viewScopes.last(where: { $0.isActiveView })
            representativeSceneIdentifier = activeView?.sceneIdentifier
        }

        viewScopes.forEach {
            $0.isCrashContextRepresentative = $0 === activeView
        }

        if activeView !== previousRepresentative {
            let representativeEvent = activeView?.latestViewEvent
            dependencies.fatalErrorContext.view = representativeEvent
            if let representativeEvent {
                dependencies.watchdogTermination?.update(viewEvent: representativeEvent)
            } else {
                dependencies.watchdogTermination?.clearView()
            }
        }
    }

    private func emitInitialEventsForRestoredViews(
        on command: RUMCommand,
        context: DatadogContext,
        writer: Writer
    ) {
        guard !restoredViewsAwaitingInitialEvent.isEmpty else {
            return
        }

        // The RUM view filter intentionally drops a session's index-0 event at
        // the exact start instant. Move this synthetic boundary update by one
        // microsecond so every restored scene has a durable baseline event.
        var initializationCommand = RUMKeepSessionAliveCommand(
            time: command.time.addingTimeInterval(0.000001),
            attributes: [:]
        )
        initializationCommand.globalAttributes = command.globalAttributes
        let pendingViews = restoredViewsAwaitingInitialEvent
        restoredViewsAwaitingInitialEvent.removeAll()

        for viewScope in pendingViews where viewScope.latestViewEvent == nil
            && viewScopes.contains(where: { $0 === viewScope }) {
            viewScope.sendSessionBoundaryViewEvent(
                on: initializationCommand,
                context: context,
                writer: writer
            )
        }
    }

    private func propagate(command: RUMCommand, context: DatadogContext, writer: Writer) {
        // Resolve once before completion can remove an inactive owning view.
        // Resource identity must outrank the current representative so an
        // unrelated action cannot count another scene's completion.
        let resourceOwnerView = (command as? RUMResourceCommand).flatMap { resourceCommand in
            viewScopes.first {
                $0.resourceScopes[resourceCommand.resourceKey] != nil
            }
        }
        let hasExactTargetView: Bool
        let routedTargetView: RUMViewScope?
        if case .view(let viewID) = command.target {
            hasExactTargetView = viewScopes.contains { $0.viewUUID == viewID }
            // Resolve once before processing mutates child scopes. In particular,
            // completing a resource can remove its inactive owning view; resolving
            // again afterward could fall through to the current same-scene view
            // and apply one completion twice.
            routedTargetView = routedView(
                for: viewID,
                command: command,
                hasExactTargetView: hasExactTargetView
            )
        } else {
            hasExactTargetView = false
            routedTargetView = nil
        }

        let targetSceneIdentifier: RUMSceneIdentifier?
        if case .scene(let sceneIdentifier) = command.target {
            targetSceneIdentifier = sceneIdentifier
        } else {
            targetSceneIdentifier = nil
        }
        let hasExactSceneBranch = targetSceneIdentifier.map { targetSceneIdentifier in
            viewScopes.contains { $0.sceneIdentifier == targetSceneIdentifier }
        } ?? false
        let activeSceneIdentifiers = Set(
            viewScopes.lazy.filter(\.isActiveView).compactMap(\.sceneIdentifier)
        )
        let shouldMigrateLegacyBranch = command is RUMStartViewCommand
            && targetSceneIdentifier.map { activeSceneIdentifiers == [$0] } == true
        let legacySceneFallback = targetSceneIdentifier != nil && !hasExactSceneBranch
            ? legacyOffViewFallback
            : nil

        viewScopes = viewScopes.compactMap { viewScope in
            guard shouldPropagate(
                command: command,
                to: viewScope,
                routedTargetView: routedTargetView,
                resourceOwnerView: resourceOwnerView,
                hasExactSceneBranch: hasExactSceneBranch,
                shouldMigrateLegacyBranch: shouldMigrateLegacyBranch,
                legacySceneFallback: legacySceneFallback
            ) else {
                if command is RUMUserActionCommand {
                    // Advance peers without attributing the recipient's action
                    // attributes or other side effects to them.
                    viewScope.expireUserActionIfNeeded(on: command, context: context, writer: writer)
                }
                return viewScope
            }
            return viewScope.process(command: command, context: context, writer: writer)
                ? viewScope
                : nil
        }
    }

    private func shouldPropagate(
        command: RUMCommand,
        to viewScope: RUMViewScope,
        routedTargetView: RUMViewScope?,
        resourceOwnerView: RUMViewScope?,
        hasExactSceneBranch: Bool,
        shouldMigrateLegacyBranch: Bool,
        legacySceneFallback: RUMViewScope?
    ) -> Bool {
        switch command.target {
        case .none:
            return false

        case .allActiveViews:
            return true

        case .scene(let sceneIdentifier):
            if hasExactSceneBranch, viewScope.sceneIdentifier == sceneIdentifier {
                return true
            }

            // Migrate the sole legacy branch when the first real scene-backed
            // view starts. This preserves the historical one-window behavior
            // for apps mixing manual and automatic view tracking without
            // letting later windows deactivate one another.
            if shouldMigrateLegacyBranch,
               viewScope.isActiveView,
               viewScope.sceneIdentifier == nil {
                return true
            }

            // A process-level placeholder is a compatibility fallback only
            // while no scene-backed branch exists. It must never receive a
            // command intended for a missing scene alongside another window.
            return viewScope === legacySceneFallback

        case .view:
            return viewScope === routedTargetView

        case .processRepresentative:
            if let stopViewCommand = command as? RUMStopViewCommand,
               let owningView = viewScopes.last(where: {
                   $0.isActiveView && $0.identity == stopViewCommand.identity
               }) {
                return viewScope === owningView
            }
            if command is RUMStartViewCommand || command is RUMStopViewCommand {
                return viewScope.sceneIdentifier == nil || viewScope === activeView
            }
            if command is RUMResourceCommand {
                if command is RUMStartResourceCommand {
                    return viewScope === activeView || viewScope === resourceOwnerView
                }
                if let resourceOwnerView {
                    return viewScope === resourceOwnerView
                }
                return viewScope === activeView
            }
            return viewScope === activeView
        }
    }

    private func resolveOperationTarget(
        for command: RUMOperationStepVitalCommand
    ) -> (target: RUMCommandTarget, view: RUMViewScope?) {
        if let explicitTarget = command.explicitTarget,
           let explicitView = operationTargetView(
               for: explicitTarget,
               command: command
           ) {
            return (explicitTarget, explicitView)
        }

        return (
            command.target,
            operationTargetView(for: command.target, command: command)
        )
    }

    private func operationTargetView(
        for target: RUMCommandTarget,
        command: RUMOperationStepVitalCommand
    ) -> RUMViewScope? {
        switch target {
        case .none:
            return nil
        case .allActiveViews, .processRepresentative:
            return activeView
        case .scene(let sceneIdentifier):
            return viewScopes.last {
                $0.isActiveView && $0.sceneIdentifier == sceneIdentifier
            }
        case .view(let viewID):
            return routedView(
                for: viewID,
                command: command,
                hasExactTargetView: viewScopes.contains { $0.viewUUID == viewID }
            )
        }
    }

    private func actionTargetView(
        for target: RUMCommandTarget,
        command: RUMUserActionCommand
    ) -> RUMViewScope? {
        switch target {
        case .none:
            return nil
        case .allActiveViews, .processRepresentative:
            return activeView
        case .scene(let sceneIdentifier):
            return viewScopes.last {
                $0.isActiveView && $0.sceneIdentifier == sceneIdentifier
            }
        case .view(let viewID):
            return routedView(
                for: viewID,
                command: command,
                hasExactTargetView: viewScopes.contains { $0.viewUUID == viewID }
            )
        }
    }

    private func isOffView(_ viewScope: RUMViewScope) -> Bool {
        viewScope.viewPath == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL
            || viewScope.viewPath == RUMOffViewEventsHandlingRule.Constants.backgroundViewURL
    }

    private func hasRoutableView(for command: RUMCommand) -> Bool {
        switch command.target {
        case .none:
            return false
        case .allActiveViews:
            return hasActiveView
        case .scene(let sceneIdentifier):
            return viewScopes.contains {
                $0.isActiveView && $0.sceneIdentifier == sceneIdentifier
            } || legacyOffViewFallback != nil
        case .view(let viewID):
            return routedView(
                for: viewID,
                command: command,
                hasExactTargetView: viewScopes.contains { $0.viewUUID == viewID }
            ) != nil
        case .processRepresentative:
            return hasActiveView
        }
    }

    private func shouldHandleOffViewCommand(_ command: RUMCommand) -> Bool {
        guard !hasRoutableView(for: command) else {
            return false
        }

        switch command.target {
        case .none:
            // Explicitly captured absence must not create a process-wide
            // placeholder view as a side effect.
            return false
        case .view:
            // A missing exact view cannot safely create a scene-less Background
            // or ApplicationLaunch branch next to live scene-backed windows.
            // Preserve the historical off-view behavior only for legacy apps
            // that have no scene-owned active branch.
            return !viewScopes.contains {
                $0.isActiveView && $0.sceneIdentifier != nil
            }
        case .allActiveViews, .scene, .processRepresentative:
            return true
        }
    }

    private func routedView(
        for viewID: RUMUUID,
        command: RUMCommand,
        hasExactTargetView: Bool
    ) -> RUMViewScope? {
        if let resourceCommand = command as? RUMResourceCommand,
           let resourceOwner = viewScopes.first(where: {
               $0.resourceScopes[resourceCommand.resourceKey] != nil
           }) {
            return resourceOwner
        }

        let exactView = hasExactTargetView
            ? viewScopes.first(where: { $0.viewUUID == viewID })
            : nil
        if let exactView, exactView.isActiveView {
            return exactView
        }

        let ownership: ViewCache.ViewOwnership
        if let exactView {
            ownership = exactView.sceneIdentifier.map(ViewCache.ViewOwnership.scene) ?? .legacy
        } else {
            ownership = dependencies.viewCache.ownership(forViewID: viewID.toRUMDataFormat)
        }

        if case .scene(let owningScene) = ownership {
            return viewScopes.last(where: {
                $0.isActiveView && $0.sceneIdentifier == owningScene
            }) ?? legacyOffViewFallback
        }

        if ownership == .legacy {
            // A known scene-less view predates scene-aware routing. Preserve its
            // historical representative fallback even after an app adopts scenes.
            return activeView
        }

        // If historical ownership has already expired from ViewCache, there is
        // no safe representative in a genuinely concurrent multi-scene app.
        // Dropping the delayed command is preferable to charging another window.
        let activeSceneIdentifiers = Set(
            viewScopes.lazy
                .filter(\.isActiveView)
                .compactMap(\.sceneIdentifier)
        )
        guard activeSceneIdentifiers.isEmpty else {
            return nil
        }

        // A view ID with no scene metadata predates scene-aware routing. Keep
        // its historical representative fallback for compatibility.
        return activeView
    }

    /// Process-global off-views predate scene routing. They are safe only when
    /// no scene-backed view is active; otherwise choosing one would charge a
    /// command from a missing scene to whichever window is representative.
    private var legacyOffViewFallback: RUMViewScope? {
        guard !viewScopes.contains(where: {
            $0.isActiveView && $0.sceneIdentifier != nil
        }) else {
            return nil
        }
        return viewScopes.last(where: {
            $0.isActiveView && $0.sceneIdentifier == nil && isOffView($0)
        })
    }
}

private extension RUMCommandTarget {
    var sceneIdentifier: RUMSceneIdentifier? {
        guard case .scene(let sceneIdentifier) = self else {
            return nil
        }
        return sceneIdentifier
    }
}
