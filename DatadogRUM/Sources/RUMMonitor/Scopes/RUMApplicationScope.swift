/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import DatadogInternal
import Foundation

internal class RUMApplicationScope: RUMScope, RUMContextProvider {
    /// Tracks the overall application state since `RUM.enable()` was called.
    private let applicationState = RUMApplicationState()

    // MARK: - Child Scopes

    // Whether the application is already active. Set to true
    // when the first session starts.
    private(set) var applicationActive = false

    /// Session scope. It gets created with the first event.
    /// Might be re-created later according to session duration constraints.
    private(set) var sessionScopes: [RUMSessionScope] = []

    /// Last active foreground views from the previous session, one per scene.
    /// Used to restore concurrent views when a new session starts after `sessionStop()`.
    private var lastActiveViews: [RUMViewScope] = []

    /// The end reason from the last active session. Used as "start reason" for the new session.
    private var lastSessionEndReason: RUMSessionScope.EndReason?

    var activeSession: RUMSessionScope? {
        get { return sessionScopes.first(where: { $0.isActive }) }
    }

    // MARK: - Initialization

    /// Container bundling dependencies for this scope.
    let dependencies: RUMScopeDependencies

    /// Handles resolution of `launchReason` during the app launch window (used primarily on tvOS and as a fallback on iOS).
    /// Buffers early RUM commands until the launch reason can be determined, then injects the resolved value and forwards them.
    let launchReasonResolver = LaunchReasonResolver(launchWindowThreshold: LaunchReasonResolver.Constants.launchWindowThreshold)
    /// Ensures the fallback to `launchReasonResolver` is logged only once when `launchReason` is unexpectedly `.uncertain` on iOS.
    private var didLogFallbackToResolver = false

    init(dependencies: RUMScopeDependencies) {
        self.dependencies = dependencies

        self.context = RUMContext(
            rumApplicationID: dependencies.rumApplicationID,
            sessionID: .nullUUID,
            isSessionActive: false,
            activeViewID: nil,
            activeViewPath: nil,
            activeViewName: nil,
            activeUserActionID: nil
        )
    }

    // MARK: - RUMContextProvider

    let context: RUMContext
    var attributes: [AttributeKey: AttributeValue] { [:] }

    // MARK: - RUMScope

    /// Entry point for processing a RUM command in the Application Scope.
    ///
    /// On iOS, we expect the `launchReason` to be resolved at SDK initialization using `task_role` or the prewarm flag.
    /// As a safeguard, we fall back to the `LaunchReasonResolver` if the `launchReason` is still `.uncertain`—
    /// in case the iOS-side assumptions fail (e.g., unhandled platform edge case or kernel API failure).
    ///
    /// On tvOS and watchOS, we always use the `LaunchReasonResolver`, since those platforms do not support
    /// `task_role` or prewarming signals.
    ///
    /// - Returns: `true` to indicate that the Application Scope should remain active.
    func process(command: RUMCommand, context: DatadogContext, writer: Writer) -> Bool {
        #if !os(tvOS) && !os(watchOS)
        guard context.launchInfo.launchReason != .uncertain else {
            if !didLogFallbackToResolver {
                dependencies.telemetry.debug("Falling back unexpectedly to 'launchReasonResolver' due to 'uncertain' launch reason")
                didLogFallbackToResolver = true
            }
            launchReasonResolver
                .deferUntilLaunchReasonResolved(command: command, context: context, writer: writer, onReady: _process(command:context:writer:))
            return true
        }
        _process(command: command, context: context, writer: writer)
        #else
        launchReasonResolver
            .deferUntilLaunchReasonResolved(command: command, context: context, writer: writer, onReady: _process(command:context:writer:))
        #endif

        return true
    }

    private func _process(command incomingCommand: RUMCommand, context: DatadogContext, writer: Writer) {
        guard var error = incomingCommand as? RUMAddCurrentViewErrorCommand else {
            processCommand(command: incomingCommand, context: context, writer: writer)
            return
        }
        let completion = RUMErrorCompletion(error.completionHandler)
        error.completionHandler = NOPCompletionHandler
        let errorWriter = RUMErrorCompletionWriter(writer: writer, errorCompletion: completion)
        processCommand(command: error, context: context, writer: errorWriter)
        completion.finish()
    }

    private func processCommand(command incomingCommand: RUMCommand, context: DatadogContext, writer: Writer) {
        var command = incomingCommand
        // `RUMSDKInitCommand` forces the creation of the initial session
        // Added in https://github.com/DataDog/dd-sdk-ios/pull/1278 to ensure that logs and traces
        // can be correlated with valid RUM session id (even if occurring before any user interaction).
        if command is RUMSDKInitCommand {
            createInitialSession(with: context, on: command)

            // RUM-6698: When the user launches an app that was not running (cold start), the expected
            // initial app state is `.inactive`:
            //
            // Ref.: https://developer.apple.com/documentation/uikit/app_and_environment/managing_your_app_s_life_cycle
            // > After launch, the system puts the app in the inactive or background state, depending on whether the UI
            // > is about to appear onscreen. When launching to the foreground, the system transitions the app to the
            // > active state automatically.
            //
            // However, for apps that initialize RUM after `application(_:didFinishLaunchingWithOptions:)`,
            // the initial state can be `.active`. Therefore, we consider both `.inactive` and `.active` as valid
            // initial states for starting the initial view.
            let appState = context.applicationStateHistory.currentState
            let sdkInitInForeground = appState == .inactive || appState == .active
            let isUserLaunch = context.launchInfo.launchReason == .userLaunch

            if sdkInitInForeground || isUserLaunch {
                // Start "ApplicationLaunch" view immediatelly:
                startApplicationLaunchView(on: command, context: context, writer: writer)
            }
            return
        }

        // If the application has not been yet activated and no sessions exist -> create the initial session
        // Added in https://github.com/DataDog/dd-sdk-ios/pull/1219 to start new session automatically when
        // a user action is sent (startView or addUserAction).
        if sessionScopes.isEmpty && !applicationActive {
            // This flow is likely stale code as`RUMSDKInitCommand` should already start the session before reaching this point
            dependencies.telemetry.debug("Starting initial session from lazy flow")
            createInitialSession(with: context, on: command)
        }

        // Create the application launch view on any command
        if !applicationActive {
            startApplicationLaunchView(on: command, context: context, writer: writer)
        }

        if activeSession == nil {
            // No active sessions, start a new one
            if !(command is RUMHandleAppLifecycleEventCommand) {
                command = startNewSession(on: command, context: context, writer: writer)
            }
        }

        // Store the last foreground view that was active before the session expired or was stopped.
        // This allows the next session to lazily restart the same view if needed.
        if let activeSession {
            var activeForegroundViews = activeSession.viewScopes.filter {
                $0.isActiveView
                    && $0.viewPath != RUMOffViewEventsHandlingRule.Constants.backgroundViewURL
            }
            if let representative = activeSession.activeView,
               let index = activeForegroundViews.firstIndex(where: { $0 === representative }) {
                activeForegroundViews.append(activeForegroundViews.remove(at: index))
            }
            if !activeForegroundViews.isEmpty {
                lastActiveViews = activeForegroundViews
            }
        }

        if command is RUMStopSessionCommand {
            applicationState.wasAnySessionStopped = true
        }

        // Can't use scope(byPropagating:context:writer) because of the extra step in looking for sessions
        // that need a refresh
        sessionScopes = sessionScopes.compactMap({ scope in
            if scope.process(command: command, context: context, writer: writer) {
                // proccss(command:context:writer) returned true, so keep the scope around
                // as it it still has work to do.
                return scope
            }

            // proccss(command:context:writer) returned false, so the scope will be deallocated at the end of
            // this execution context. End the "RUM Session Ended" metric:
            defer { dependencies.sessionEndedMetric.endMetric(sessionID: scope.sessionUUID, with: context) }

            // proccss(command:context:writer) returned false, but if the scope is still active
            // it means the session reached one of the end reasons
            guard let endReason = scope.endReason else {
                // Sanity telemetry, we don't expect reaching this flow
                dependencies.telemetry.error("A session has ended with no 'end reason'")
                return nil
            }

            // Store "end reason" so it will be used as "start reason" for next session
            lastSessionEndReason = endReason

            switch endReason {
            case .timeOut, .maxDuration:
                applicationState.wasPreviousSessionStopped = false
                if !(command is RUMHandleAppLifecycleEventCommand) {
                    // Replace this session scope with the scope for refreshed session:
                    return refresh(expiredSession: scope, on: command, context: context, writer: writer)
                } else {
                    // The next session will start lazily on next event
                    return nil
                }
            case .stopAPI:
                // Remove this session scope (a new on will be started upon receiving user interaction):
                applicationState.wasPreviousSessionStopped = true
                return nil
            }
        })

        // Sanity telemetry, only end up with one active session
        let activeSessions = sessionScopes.filter { $0.isActive }
        if activeSessions.count > 1 {
            dependencies.telemetry.error("An application has \(activeSessions.count) active sessions")
        }
        if activeSessions.isEmpty {
            // There is no need to call `sessionScopeDidUpdate` here if we have
            // active sessions because we are certain it was already called when
            // sessions were created.
            sessionScopeDidUpdate(nil)
        }
    }

    // MARK: - Private

    /// Sanity count to make sure initial session is created only once.
    private var didCreateInitialSessionCount = 0

    /// Starts initial RUM Session.
    private func createInitialSession(with context: DatadogContext, on command: RUMCommand) {
        if didCreateInitialSessionCount > 0 { // Sanity check
            dependencies.telemetry.error("Creating initial session \(didCreateInitialSessionCount) extra time(s) due to \(type(of: command)) (previous end reason: \(lastSessionEndReason?.rawValue ?? "unknown"))")
        }
        didCreateInitialSessionCount += 1

        var startPrecondition: RUMSessionPrecondition? = nil

        if context.applicationStateHistory.currentState == .background {
            switch context.launchInfo.launchReason {
            case .userLaunch:
                startPrecondition = .userAppLaunch // UISceneDelegate-based apps always start in background
            case .backgroundLaunch, .prewarming:
                startPrecondition = preconditionForNewBackgroundSession(context: context)
            @unknown default:
                dependencies.telemetry.error("Creating initial session in background with unexpected launch reason: \(context.launchInfo.launchReason)")
            }
        } else {
            startPrecondition = .userAppLaunch
        }

        let initialSession = RUMSessionScope(
            isInitialSession: true,
            parent: self,
            startTime: context.sdkInitDate,
            startPrecondition: startPrecondition,
            context: context,
            dependencies: dependencies,
            applicationState: applicationState
        )

        lastSessionEndReason = nil
        sessionScopes.append(initialSession)
        sessionScopeDidUpdate(initialSession)
    }

    /// Starts new RUM Session immediately after previous one expires or time outs. It transfers some of the state from the expired session to the new one.
    private func refresh(expiredSession: RUMSessionScope, on incomingCommand: RUMCommand, context: DatadogContext, writer: Writer) -> RUMSessionScope {
        var startPrecondition: RUMSessionPrecondition? = nil

        // If the app is in background, use the background-aware precondition; otherwise fall through to the end-reason logic.
        if context.applicationStateHistory.currentState == .background,
           let backgroundPrecondition = preconditionForNewBackgroundSession(context: context) {
            startPrecondition = backgroundPrecondition
        } else if lastSessionEndReason == .timeOut {
            startPrecondition = .inactivityTimeout
        } else if lastSessionEndReason == .maxDuration {
            startPrecondition = .maxDuration
        } else {
            dependencies.telemetry.error("Failed to determine session precondition for REFRESHED session with end reason: \(lastSessionEndReason?.rawValue ?? "unknown")")
        }

        var previousViews = expiredSession.viewScopes.filter {
            $0.isActiveView && $0.viewPath != RUMOffViewEventsHandlingRule.Constants.backgroundViewURL
        }
        if let representative = expiredSession.activeView,
           let index = previousViews.firstIndex(where: { $0 === representative }) {
            previousViews.append(previousViews.remove(at: index))
        }
        let command = previousViews.resolvingNavigationOwner(of: incomingCommand)
        let viewsToResume = viewsToRestore(on: command, from: previousViews, context: context)

        let refreshedSession = RUMSessionScope(
            from: expiredSession,
            startTime: command.time,
            startPrecondition: startPrecondition,
            context: context,
            transferActiveView: !viewsToResume.isEmpty,
            applicationState: applicationState,
            resumingViewScopes: viewsToResume
        )
        sessionScopeDidUpdate(refreshedSession)
        lastActiveViews = []
        lastSessionEndReason = nil
        _ = refreshedSession.process(command: command, context: context, writer: writer)
        return refreshedSession
    }

    private func startNewSession(on incomingCommand: RUMCommand, context: DatadogContext, writer: Writer) -> RUMCommand {
        let command = lastActiveViews.resolvingNavigationOwner(of: incomingCommand)
        var startPrecondition: RUMSessionPrecondition? = nil

        // If the app is in background, use the background-aware precondition; otherwise fall through to the end-reason logic.
        if context.applicationStateHistory.currentState == .background,
           let backgroundPrecondition = preconditionForNewBackgroundSession(context: context) {
            startPrecondition = backgroundPrecondition
        } else if lastSessionEndReason == .stopAPI {
            startPrecondition = .explicitStop
        } else if lastSessionEndReason == .timeOut {
            startPrecondition = .inactivityTimeout
        } else if lastSessionEndReason == .maxDuration {
            startPrecondition = .maxDuration
        } else {
            dependencies.telemetry.error("Failed to determine session precondition for NEW session with end reason: \(lastSessionEndReason?.rawValue ?? "unknown")")
        }

        if didCreateInitialSessionCount > 0 { // Sanity check
            // This is a non-initial session (initial sessions are created via `RUMSDKInitCommand`)
            dependencies.telemetry.debug("Starting new session triggered by \(type(of: command)). Previous session was stopped for the following reason: \(startPrecondition?.rawValue ?? "unknown")")
        }

        let viewsToResume = viewsToRestore(on: command, from: lastActiveViews, context: context)

        let newSession = RUMSessionScope(
            isInitialSession: false,
            parent: self,
            startTime: command.time,
            startPrecondition: startPrecondition,
            context: context,
            dependencies: dependencies,
            applicationState: applicationState,
            resumingViewScopes: viewsToResume
        )
        lastActiveViews = []
        lastSessionEndReason = nil
        sessionScopes.append(newSession)
        sessionScopeDidUpdate(newSession)
        return command
    }

    /// Both immediate and delayed boundaries restore the same eligible peers.
    /// Navigation ownership is already resolved against the previous session.
    private func viewsToRestore(on command: RUMCommand, from views: [RUMViewScope], context: DatadogContext) -> [RUMViewScope] {
        guard context.applicationStateHistory.currentState == .active else {
            return []
        }
        let shouldRestart: Bool
        switch lastSessionEndReason {
        case .stopAPI:
            shouldRestart = command.shouldRestartLastViewAfterSessionStop
        case .timeOut, .maxDuration:
            shouldRestart = command.shouldRestartLastViewAfterSessionExpiration
        case nil:
            return []
        }
        if shouldRestart {
            return views
        }
        if command is RUMStartViewCommand || command is RUMStopViewCommand {
            return views.excludingViewTargeted(by: command.target)
        }
        return []
    }

    private func sessionScopeDidUpdate(_ sessionScope: RUMSessionScope?) {
        dependencies.onSessionUpdate(sessionScope)
    }

    /// Forces the `ApplicationLaunchView` to be started.
    /// Added as part of https://github.com/DataDog/dd-sdk-ios/pull/1290 to separate creation of first view
    /// from creation of initial session due to receiving `RUMSDKInitCommand`. Starting from RUM-1649 the "application launch" view
    /// is started on SDK init only when the app is launched by user with no prewarming or when app was prewarmed but SDK was initialized
    /// after it became active.
    private func startApplicationLaunchView(on command: RUMCommand, context: DatadogContext, writer: Writer) {
        applicationActive = true

        let isUserLaunch = context.launchInfo.launchReason == .userLaunch
        let isPrewarmed = context.launchInfo.launchReason == .prewarming
        let isBackgroundLaunch = context.launchInfo.launchReason == .backgroundLaunch
        let isStartedInForeground = command is RUMSDKInitCommand && context.applicationStateHistory.currentState != .background
        guard isUserLaunch || (isPrewarmed && isStartedInForeground) || (isBackgroundLaunch && isStartedInForeground) else {
            return
        }

        // Immediately start the ApplicationLaunchView for the new session
        _ = process(
            command: RUMApplicationStartCommand(
                time: command.time,
                globalAttributes: command.globalAttributes,
                attributes: command.attributes
            ),
            context: context,
            writer: writer
        )
    }

    private func preconditionForNewBackgroundSession(context: DatadogContext) -> RUMSessionPrecondition? {
        switch context.launchInfo.launchReason {
        case .backgroundLaunch:
            return .backgroundLaunch
        case .prewarming:
            return .prewarm
        case .userLaunch:
            // Normal: a user-launched process went to background. Caller uses end-reason-based precondition.
            return nil
        @unknown default:
            dependencies.telemetry.error(
                "Starting session in background with unexpected launch reason: \(context.launchInfo.launchReason)"
            )
            return nil
        }
    }
}

private extension Array where Element == RUMViewScope {
    /// The previous representative is last. A manual stop first matches its
    /// identity; choosing a representative after exclusion would change owners.
    func resolvingNavigationOwner(of command: RUMCommand) -> RUMCommand {
        guard command.target == .processRepresentative else {
            return command
        }
        if var start = command as? RUMStartViewCommand,
           let scene = last?.sceneIdentifier {
            start.target = .scene(scene)
            return start
        }
        if var stop = command as? RUMStopViewCommand,
           let scene = (last(where: { $0.identity == stop.identity }) ?? last)?.sceneIdentifier {
            stop.target = .scene(scene)
            return stop
        }
        return command
    }

    func excludingViewTargeted(by target: RUMCommandTarget) -> [RUMViewScope] {
        switch target {
        case .scene(let sceneIdentifier):
            return filter { $0.sceneIdentifier != sceneIdentifier }
        case .view(let viewID):
            return filter { $0.viewUUID != viewID }
        case .processRepresentative:
            // `lastActiveViews` keeps the representative branch last.
            return isEmpty ? [] : Array(dropLast())
        case .none, .allActiveViews:
            return []
        }
    }
}

/// Finishes an error once processing and every scheduled write have completed.
/// The processing reservation also covers dropped errors with no recipient.
private final class RUMErrorCompletion {
    private let lock = NSLock()
    private var pending = 1
    private var completion: CompletionHandler?

    init(_ completion: @escaping CompletionHandler) {
        self.completion = completion
    }

    func beginWrite() {
        lock.lock()
        pending += 1
        lock.unlock()
    }

    func finish() {
        lock.lock()
        pending -= 1
        let callback = pending == 0 ? completion : nil
        if pending == 0 {
            completion = nil
        }
        lock.unlock()
        callback?()
    }
}

private struct RUMErrorCompletionWriter: Writer {
    let writer: Writer
    let errorCompletion: RUMErrorCompletion

    func write<T: Encodable, M: Encodable>(value: T, metadata: M?, completion: @escaping CompletionHandler) {
        errorCompletion.beginWrite()
        writer.write(value: value, metadata: metadata) {
            completion()
            self.errorCompletion.finish()
        }
    }
}
