/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
@_spi(Internal) import DatadogInternal

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
            let previousActiveViewUUID = activeView?.viewUUID
            let nextActiveView = viewScopes.last(where: { $0.isActiveView })
            if !dependencies.isMultiSceneTrackingEnabled, previousActiveViewUUID != nextActiveView?.viewUUID, let previousActiveViewUUID {
                dependencies.viewCache.markInactive(id: previousActiveViewUUID.toRUMDataFormat)
            }
            activeView = sceneState?.representativeViewID.flatMap { id in
                viewScopes.last(where: { $0.isActiveView && $0.viewUUID == id })
            } ?? nextActiveView
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

    /// Current active view.
    private var activeView: RUMViewScope?

    /// Allocated only for the resolved On path; the legacy metric remains process-wide.
    enum NavigationDestination {
        case ownedScene(RUMSceneIdentifier?)
        case unresolved
    }

    private final class SceneState {
        var navigationDestination: NavigationDestination?
        var representativeViewID: RUMUUID?
        var interactionMetrics: [RUMSceneIdentifier: INVMetricTracking?] = [:]
        var restoredViews: [RUMViewScope] = []
    }

    private let sceneState: SceneState?

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
            if oldValue == nil, endReason != nil {
                deactivateActiveView()
            }
            if endReason != nil {
                dependencies.timeseriesCollector?.stop(sessionID: sessionUUID.toRUMDataFormat)
            }
        }
    }

    /// Counter to track the index of views in this session. Starts at 0 for the first view.
    private var nextViewIndex: Int = 0

    private lazy var interactionToNextViewMetric = dependencies.interactionToNextViewMetricFactory()

    init(
        isInitialSession: Bool,
        parent: RUMContextProvider,
        startTime: Date,
        startPrecondition: RUMSessionPrecondition?,
        context: DatadogContext,
        dependencies: RUMScopeDependencies,
        applicationState: RUMApplicationState,
        resumingViewScope: RUMViewScope? = nil,
        resumingViewScopes: [RUMViewScope]? = nil,
        navigationDestination: NavigationDestination? = nil,
        presetSessionUUID: RUMUUID? = nil
    ) {
        // `presetSessionUUID` is created synchronously in `RUM.enable()` for the initial session, so the
        // sampler derived from it is exposed through `SessionSampler` before `RUM.enable()` returns.
        // Every other session generates its ID here, as before.
        let sessionUUID = presetSessionUUID ?? dependencies.rumUUIDGenerator.generateUnique()

        self.parent = parent
        self.dependencies = dependencies
        self.sceneState = dependencies.isMultiSceneTrackingEnabled ? SceneState() : nil
        self.sceneState?.navigationDestination = navigationDestination
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
        if !dependencies.isMultiSceneTrackingEnabled {
            _ = interactionToNextViewMetric
        }

        if sampler.isSampled {
            // Start tracking "RUM Session Ended" metric for this session
            dependencies.sessionEndedMetric.startMetric(
                sessionID: sessionUUID,
                precondition: startPrecondition,
                context: context
            )
        }

        if let viewScope = resumingViewScope {
            startView(
                isInitialView: false,
                dependencies: dependencies,
                identity: viewScope.identity,
                path: viewScope.viewPath,
                name: viewScope.viewName,
                customTimings: [:],
                startTime: startTime,
                serverTimeOffset: viewScope.serverTimeOffset,
                hasReplay: context.hasReplay
            )
        }

        if let resumingViewScopes, sceneState != nil {
            restoreViews(resumingViewScopes, at: startTime, context: context)
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
        triggeringCommand: RUMCommand? = nil
    ) {
        let navigationDestination = expiredSession.sceneState == nil ? nil : Self.resolveNavigationDestination(
            on: triggeringCommand,
            representative: expiredSession.activeView?.sceneIdentifier,
            cache: expiredSession.dependencies.viewCache
        )
        self.init(
            // If the expired session was marked as "initial" but didn’t track any views, mark this new session as the new "initial".
            isInitialSession: expiredSession.state.isInitialSession && !expiredSession.state.hasTrackedAnyView,
            parent: expiredSession.parent,
            startTime: startTime,
            startPrecondition: startPrecondition,
            context: context,
            dependencies: expiredSession.dependencies,
            applicationState: applicationState,
            navigationDestination: navigationDestination
        )

        // Multi-scene rollover restores peers independently of the triggering navigation.
        if sceneState != nil, context.applicationStateHistory.currentState.isRunningInForeground {
            let foregroundViews = expiredSession.foregroundViewsForRestoration
            let views = viewsToRestore(foregroundViews, on: triggeringCommand, restoreAll: transferActiveView)
            restoreViews(views, at: startTime, context: context)
            return
        }

        // Transfer active View to new `RUMViewScope`:
        if transferActiveView {
            if let lastActiveView = expiredSession.viewScopes.last(where: { $0.isActiveView }) {
                let activeView = RUMViewScope(
                    isInitialView: false,
                    parent: self,
                    dependencies: dependencies,
                    identity: lastActiveView.identity,
                    path: lastActiveView.viewPath,
                    name: lastActiveView.viewName,
                    customTimings: lastActiveView.customTimings,
                    startTime: startTime,
                    serverTimeOffset: context.serverTimeOffset,
                    interactionToNextViewMetric: interactionToNextViewMetric,
                    viewIndexInSession: nextViewIndex
                )
                self.viewScopes = [activeView]
                self.activeView = activeView
                dependencies.viewCache.insert(
                    id: activeView.viewUUID.toRUMDataFormat,
                    timestamp: startTime.timeIntervalSince1970.dd.toInt64Milliseconds,
                    hasReplay: context.hasReplay,
                    isActive: true
                )
                nextViewIndex += 1
            } else {
                self.viewScopes = []
            }
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

    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        let command = command.resolvingResourceOwners(in: viewScopes)
        if hasTimedOut(currentTime: command.time) {
            endReason = .timeOut
            return false // end this session (no longer keep the session scope)
        }
        if hasExpired(currentTime: command.time) {
            endReason = .maxDuration
            return false // end this session (no longer keep the session scope)
        }

        if command.isUserInteraction {
            lastInteractionTime = command.time
        }

        if !sampler.isSampled {
            // Make sure sessions end even if they are not sampled
            if command is RUMStopSessionCommand {
                endReason = .stopAPI
                return false // end this session (no longer keep the session scope)
            }

            return true // keep this session until it gets ended by any `endReason`
        }

        if let sceneState, sceneState.navigationDestination == nil {
            sceneState.navigationDestination = Self.resolveNavigationDestination(
                on: command,
                representative: activeView?.sceneIdentifier,
                cache: dependencies.viewCache
            )
        }
        defer { sceneState?.navigationDestination = nil }

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
                if sceneState == nil || canStartView {
                    startView(on: startViewCommand, context: context)
                }
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

            case let operationStepVitalCommand as RUMOperationStepVitalCommand:
                // Forward command to the feature operation manager
                featureOperationManager.process(
                    operationStepVitalCommand,
                    context: context,
                    writer: writer,
                    activeView: activeView
                )
            case let command as RUMTimeToInitialDisplayCommand:
                appLaunchManager.process(command, context: context, writer: writer, activeView: activeView)
                dependencies.renderLoopObserver?.unregister(dependencies.firstFrameReader)
                // command doesn't need to be propagated to other scopes
                return true
            case let command as RUMTimeToFullDisplayCommand:
                appLaunchManager.process(command, context: context, writer: writer, activeView: activeView)
                // command doesn't need to be propagated to other scopes
                return true
            default:
                if !hasActiveView && (sceneState == nil || offViewTarget(of: command) == .processRepresentative) {
                    handleOffViewCommand(command: command, context: context, writer: writer)
                }
            }
        }

        // Keep the legacy fanout and expiry position unchanged when the flag is Off.
        if sceneState != nil {
            emitRestoredViews(on: command, context: context, writer: writer)
            propagateOwned(command, context: context, writer: writer)
        } else {
            viewScopes = viewScopes.scopes(byPropagating: command, context: context, writer: writer)
        }

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
            sceneIdentifier: sceneState == nil ? nil : navigationScene
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
            interactionToNextViewMetric: metric(for: sceneIdentifier),
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
            isActive: true,
            sceneIdentifier: sceneIdentifier
        )
    }

    deinit {
        deactivateActiveView()
    }

    private func deactivateActiveView() {
        if sceneState != nil {
            for view in viewScopes where view.isActiveView {
                dependencies.viewCache.markInactive(id: view.viewUUID.toRUMDataFormat)
            }
            return
        }
        guard let activeView else {
            return
        }
        dependencies.viewCache.markInactive(id: activeView.viewUUID.toRUMDataFormat)
    }

    // MARK: - Flagged scene ownership

    private func metric(for scene: RUMSceneIdentifier?) -> INVMetricTracking? {
        guard let sceneState, let scene else {
            return interactionToNextViewMetric
        }
        if let metric = sceneState.interactionMetrics[scene] {
            return metric
        }
        let metric = dependencies.interactionToNextViewMetricFactory()
        sceneState.interactionMetrics.updateValue(metric, forKey: scene)
        return metric
    }

    private var canStartView: Bool {
        if let destination = sceneState?.navigationDestination, case .ownedScene = destination {
            return true
        }
        return false
    }

    private var navigationScene: RUMSceneIdentifier? {
        if let destination = sceneState?.navigationDestination, case .ownedScene(let scene) = destination {
            return scene
        }
        return nil
    }

    /// Freeze ownership before restoration or cache insertion can change its lookup.
    static func resolveNavigationDestination(
        on command: RUMCommand?,
        representative: RUMSceneIdentifier?,
        cache: ViewCache
    ) -> NavigationDestination? {
        guard let command, command is RUMStartViewCommand || command is RUMStopViewCommand else {
            return nil
        }
        switch command.target {
        case .scene(let scene):
            return .ownedScene(scene)
        case .processRepresentative:
            return .ownedScene(representative)
        case .view(let id):
            switch cache.ownership(forViewID: id.toRUMDataFormat) {
            case .scene(let scene): return .ownedScene(scene)
            case .legacy: return .ownedScene(representative)
            case .unknown: return .unresolved
            }
        case .none, .allActiveViews, .continuousAction:
            return .unresolved
        }
    }

    /// A navigation replaces its own scene; unrelated foreground peers are restored.
    var foregroundViewsForRestoration: [RUMViewScope] {
        let views = viewScopes.filter {
            $0.isActiveView && $0.viewPath != RUMOffViewEventsHandlingRule.Constants.backgroundViewURL
        }
        guard let activeView, views.contains(where: { $0 === activeView }) else {
            return views
        }
        // Preserve deterministic order while keeping the last-interacted representative last.
        return views.filter { $0 !== activeView } + [activeView]
    }

    private func viewsToRestore(_ views: [RUMViewScope], on command: RUMCommand?, restoreAll: Bool) -> [RUMViewScope] {
        guard sceneState != nil else {
            return []
        }
        if let command, command is RUMStartViewCommand || command is RUMStopViewCommand {
            guard let destination = sceneState?.navigationDestination, case .ownedScene(let scene) = destination else {
                return views
            }
            return views.filter { $0.sceneIdentifier != scene }
        }
        return restoreAll ? views : []
    }

    private func restoreViews(_ views: [RUMViewScope], at time: Date, context: DatadogContext) {
        for view in views {
            startView(
                isInitialView: false,
                dependencies: dependencies,
                identity: view.identity,
                path: view.viewPath,
                name: view.viewName,
                customTimings: view.customTimings,
                startTime: time,
                serverTimeOffset: context.serverTimeOffset,
                hasReplay: context.hasReplay,
                sceneIdentifier: view.sceneIdentifier,
                didReceiveStartCommand: true
            )
            if let restored = viewScopes.last {
                sceneState?.restoredViews.append(restored)
            }
        }
    }

    private func emitRestoredViews(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        guard let sceneState, !sceneState.restoredViews.isEmpty else {
            return
        }
        // The index0 initial-view filter intentionally drops a zero-duration baseline.
        // Emit at a representable positive duration without forwarding the trigger to peers.
        let baseline = RUMKeepSessionAliveCommand(
            time: command.time.addingTimeInterval(0.000001),
            globalAttributes: command.globalAttributes,
            attributes: [:]
        )
        for view in sceneState.restoredViews {
            view.emitRestoredBaseline(on: baseline, context: context, writer: writer)
        }
        sceneState.restoredViews.removeAll()
    }

    /// Keep source-less automatic Start eligible for the existing off-view fallback.
    private func offViewTarget(of command: RUMCommand) -> RUMCommandTarget {
        if command is RUMStartUserActionCommand, case .continuousAction(let ownership) = command.target {
            return ownership.sourceTarget
        }
        return command.target
    }

    /// Queue-only join, before application-level session creation or refresh.
    func ownsContinuousAction(_ ownership: RUMContinuousActionOwnership, at date: Date) -> Bool {
        guard isActive, ownership.owner.isValid, !ownership.isClosed,
              !Self.hasExpired(sessionStartTime: sessionStartTime, currentTime: date),
              !Self.hasTimedOut(lastInteractionTime: lastInteractionTime, currentTime: date),
              let claim = ownership.claim, claim.sessionID == sessionUUID else {
            return false
        }
        return viewScopes.contains { view in
            view.viewUUID == claim.viewID && view.userActionScope?.isContinuous == true
                && view.userActionScope?.actionUUID == claim.actionID
        }
    }

    private func effectiveTarget(of command: RUMCommand) -> RUMCommandTarget {
        let explicit = (command as? RUMExplicitViewTargetCommand)?.explicitTarget
            ?? (command as? RUMUserActionCommand)?.explicitTarget
        if let explicit {
            if case .view(let id) = explicit {
                if viewScopes.contains(where: { $0.isActiveView && $0.viewUUID == id }) {
                    return explicit
                }
            } else if !activeRecipients(for: explicit).isEmpty {
                return explicit
            }
        }
        // Invalid optional API override preserves its independently inferred owner.
        return command.target
    }

    private func activeRecipients(for target: RUMCommandTarget) -> [RUMViewScope] {
        switch target {
        case .none, .continuousAction:
            return []
        case .allActiveViews:
            return viewScopes.filter { $0.isActiveView }
        case .processRepresentative:
            return activeView.map { [$0] } ?? []
        case .scene(let scene):
            return viewScopes.filter { $0.isActiveView && $0.sceneIdentifier == scene }
        case .view(let id):
            if let view = viewScopes.last(where: { $0.isActiveView && $0.viewUUID == id }) {
                return [view]
            }
            switch dependencies.viewCache.ownership(forViewID: id.toRUMDataFormat) {
            case .scene(let scene):
                return viewScopes.filter { $0.isActiveView && $0.sceneIdentifier == scene }
            case .legacy:
                return activeView.map { [$0] } ?? []
            case .unknown:
                return []
            }
        }
    }

    private func recipients(for command: RUMCommand) -> [RUMViewScope] {
        if case .continuousAction(let ownership) = command.target {
            if command is RUMStartUserActionCommand, ownership.canClaim {
                return activeRecipients(for: ownership.sourceTarget)
            }
            if command is RUMStopUserActionCommand,
               ownsContinuousAction(ownership, at: command.time), let claim = ownership.claim {
                return viewScopes.filter {
                    $0.viewUUID == claim.viewID && $0.userActionScope?.actionUUID == claim.actionID
                }
            }
            return []
        }
        if let completion = command as? RUMResourceCompletionCommand {
            if let ids = completion.owningViewIDs, !ids.isEmpty {
                return viewScopes.filter { ids.contains($0.viewUUID) }
            }
            return completion.isAutomatic ? [] : (activeView.map { [$0] } ?? [])
        }
        if let resource = command as? RUMResourceCommand, !(command is RUMStartResourceCommand) {
            return viewScopes.filter { $0.resourceScopes[resource.resourceKey] != nil }
        }
        if command is RUMStopSessionCommand || command is RUMHandleAppLifecycleEventCommand || command is RUMOperationStepVitalCommand {
            return viewScopes
        }
        if command is RUMStartViewCommand || command is RUMStopViewCommand {
            guard let destination = sceneState?.navigationDestination, case .ownedScene(let scene) = destination else {
                return []
            }
            return viewScopes.filter {
                $0.sceneIdentifier == scene
                    || (command is RUMStartViewCommand && $0.viewPath == RUMOffViewEventsHandlingRule.Constants.applicationLaunchViewURL)
            }
        }
        if command is RUMStopUserActionCommand, case .view(let id) = effectiveTarget(of: command) {
            return viewScopes.filter { $0.viewUUID == id && $0.userActionScope != nil }
        }
        return activeRecipients(for: effectiveTarget(of: command))
    }

    private func propagateOwned(_ command: RUMCommand, context: DatadogContext, writer: Writer) {
        let selected = recipients(for: command)
        let selectedIDs = Set(selected.map { $0.viewUUID })
        if command.isUserInteraction, let recipient = selected.last(where: { $0.isActiveView }) {
            sceneState?.representativeViewID = recipient.viewUUID
        }
        viewScopes = viewScopes.compactMap { view in
            if selectedIDs.contains(view.viewUUID) {
                return view.process(command: command, context: context, writer: writer) ? view : nil
            }
            // A peer's time advances, but the foreign command cannot change its attributes/counters.
            view.expireActionIfNeeded(on: command, context: context, writer: writer)
            return view
        }
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
            hasReplay: context.hasReplay
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
            hasReplay: context.hasReplay
        )
    }

    private func hasTimedOut(currentTime: Date) -> Bool {
        Self.hasTimedOut(lastInteractionTime: lastInteractionTime, currentTime: currentTime)
    }

    private func hasExpired(currentTime: Date) -> Bool {
        Self.hasExpired(sessionStartTime: sessionStartTime, currentTime: currentTime)
    }
}
