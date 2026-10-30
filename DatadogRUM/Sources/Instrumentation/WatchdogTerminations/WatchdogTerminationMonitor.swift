/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import DatadogInternal

/// Monitors the Watchdog Termination events and reports them to Datadog.
internal final class WatchdogTerminationMonitor {
    /// The state of the Watchdog Termination Monitor.
    enum State {
        /// The monitor is waiting for the first launch report. RUM updates are buffered.
        case initialized
        /// The monitor has started and is listening to the changes.
        case started
        /// The monitor is checking the previous launch. RUM updates are buffered.
        case starting
        /// The monitor has stopped and is not listening to the changes.
        case stopped
    }

    enum ErrorMessages {
        static let failedToCheckWatchdogTermination = "Failed to check if Watchdog Termination occurred"
        static let detectedWatchdogTermination = "Based on heuristics, previous app session was terminated by Watchdog"
        static let failedToReadViewEvent = "Failed to read the view event from the data store"
        static let rumViewEventUpdated = "RUM View event updated"
        static let sessionWasStopped = "Watchdog Termination is not reported because the RUM session was stopped"
        static let failedToSendWatchdogTermination = "Failed to send Watchdog Termination event"
    }

    let checker: WatchdogTerminationChecker
    let appStateManager: AppStateManager
    let feature: FeatureScope
    let reporter: WatchdogTerminationReporting
    let storage: Storage?

    /// The status of the monitor  indicating if it is active or not.
    /// When it is active, it listens to the app state changes and updates the app state in the data store.
    @ReadWriteLock
    internal var currentState: State

    /// What the monitor knows about RUM sessions and views. Updated from the RUM queue and when the monitor starts.
    private struct Tracking {
        /// Stopped sessions whose scopes can still emit view updates.
        var stoppedSessionIDs: Set<String> = []
        /// The last view update received before startup completes. It is saved once the monitor has started.
        var pendingViewEvent: RUMViewEvent?
        /// If the RUM session was stopped before startup completes. The stop is saved once the monitor has started.
        var hasPendingSessionStop = false
    }

    @ReadWriteLock
    private var tracking = Tracking()

    init(
        appStateManager: AppStateManager,
        checker: WatchdogTerminationChecker,
        storage: Storage?,
        feature: FeatureScope,
        reporter: WatchdogTerminationReporting
    ) {
        self.checker = checker
        self.appStateManager = appStateManager
        self.feature = feature
        self.reporter = reporter
        self.storage = storage
        self.currentState = .initialized
    }

    /// Starts the Watchdog Termination Monitor.
    /// - Parameter launchReport: The launch report containing information about the app launch (if available).
    func start(launchReport: LaunchReport) {
        var shouldStart = false
        _tracking.mutate { _ in
            guard currentState == .initialized else {
                return
            }
            currentState = .starting
            shouldStart = true
        }
        guard shouldStart else {
            return
        }
        sendWatchTerminationIfFound(launch: launchReport) { [weak self] in
            self?.didStart()
        }
    }

    /// Marks the monitor as started and saves the stop and the view update received while it was starting.
    private func didStart() {
        _tracking.mutate { tracking in
            guard currentState == .starting else {
                return
            }
            currentState = .started
            if tracking.hasPendingSessionStop {
                tracking.hasPendingSessionStop = false
                saveSessionStop()
            }
            if let viewEvent = tracking.pendingViewEvent {
                tracking.pendingViewEvent = nil
                save(viewEvent: viewEvent)
            }
        }
    }

    /// Updates the Watchdog Termination Monitor with the given view event.
    ///
    /// Note: This is a simpler but disk intensive way to store the view event in the data store,
    /// because we currently don't offer a way to read the view events from the written batches.
    /// This is deliberately done to avoid the complexity of reading the view events from the batches.
    /// You can disable Watchdog Terminations tracking by setting `RUM.Configuration.trackWatchdogTerminations` to false.
    ///
    /// - Parameter viewEvent: The view event which is used to report the Watchdog Termination event.
    func update(viewEvent: RUMViewEvent) {
        _tracking.mutate { tracking in
            guard !tracking.stoppedSessionIDs.contains(viewEvent.session.id) else {
                return
            }

            switch currentState {
            case .started:
                save(viewEvent: viewEvent)
            case .initialized, .starting:
                // The saved view event might be currently used to report the Watchdog Termination event,
                // so the update is saved once the monitor has started.
                tracking.pendingViewEvent = viewEvent
            case .stopped:
                break
            }
        }
    }

    /// Notifies that the RUM session was stopped with `stopSession()`. A Watchdog Termination is not reported
    /// until a view of another session is tracked.
    ///
    /// - Parameter sessionID: The ID of the stopped session.
    func sessionDidStop(sessionID: String) {
        _tracking.mutate { tracking in
            tracking.stoppedSessionIDs.insert(sessionID)
            tracking.pendingViewEvent = nil

            switch currentState {
            case .started:
                saveSessionStop()
            case .initialized, .starting:
                // The saved stop might be currently used to report the Watchdog Termination event,
                // so it is saved once the monitor has started.
                tracking.hasPendingSessionStop = true
            case .stopped:
                break
            }
        }
    }

    /// Releases bookkeeping once a session scope can no longer emit view updates. The persisted stop is kept.
    func sessionDidComplete(sessionID: String) {
        _tracking.mutate { tracking in
            tracking.stoppedSessionIDs.remove(sessionID)
        }
    }

    private func save(viewEvent: RUMViewEvent) {
        DD.logger.debug(ErrorMessages.rumViewEventUpdated)
        feature.rumDataStore.setValue(viewEvent, forKey: .watchdogRUMViewEvent)
    }

    private func saveSessionStop() {
        // Store the stop in the view record itself. A failed replacement write cannot expose an older view
        // by independently clearing a stop marker. Existing saved views remain readable as optional values.
        feature.rumDataStore.setValue(Optional<RUMViewEvent>.none, forKey: .watchdogRUMViewEvent)
    }

    /// Checks if the app was terminated by Watchdog and sends the Watchdog Termination event to Datadog.
    /// - Parameter launch: The launch report containing information about the app launch.
    private func sendWatchTerminationIfFound(launch: LaunchReport, completion: @escaping () -> Void) {
        checker.isWatchdogTermination(launch: launch) { [weak self] isWatchdogTermination, state  in
            if isWatchdogTermination, let state = state {
                DD.logger.debug(ErrorMessages.detectedWatchdogTermination)
                self?.sendWatchTermination(state: state, completion: completion)
            } else {
                completion()
            }
        }
    }

    /// Sends the Watchdog Termination event to Datadog with the given state, unless the RUM session was stopped
    /// with `stopSession()` and no view was tracked since.
    /// - Parameter state: The app state when the Watchdog Termination occurred.
    private func sendWatchTermination(state: AppStateInfo, completion: @escaping () -> Void) {
        feature.context { [weak self] context in
            do {
                let likelyCrashedAt = try self?.storage?.mostRecentModifiedFileAt(before: context.launchInfo.processLaunchDate)
                self?.feature.rumDataStore.value(forKey: .watchdogRUMViewEvent) { [weak self] (savedView: RUMViewEvent??) in
                    // A stored null means tracking stopped; outer nil means missing or unreadable data.
                    switch savedView {
                    case .some(.some(let viewEvent)):
                        self?.reporter.send(date: likelyCrashedAt, state: state, viewEvent: viewEvent)
                    case .some(.none):
                        DD.logger.debug(ErrorMessages.sessionWasStopped)
                    case .none:
                        DD.logger.error(ErrorMessages.failedToReadViewEvent)
                        self?.feature.telemetry.error(ErrorMessages.failedToReadViewEvent)
                    }
                    completion()
                }
            } catch {
                DD.logger.error(ErrorMessages.failedToSendWatchdogTermination, error: error)
                self?.feature.telemetry.error(ErrorMessages.failedToSendWatchdogTermination, error: error)
                completion()
            }
        }
    }

    /// Stops the Watchdog Termination Monitor.
    func stop() {
        _tracking.mutate { tracking in
            currentState = .stopped
            tracking.pendingViewEvent = nil
            tracking.hasPendingSessionStop = false
        }
    }
}

extension WatchdogTerminationMonitor: Flushable {
    /// Flushes the Watchdog Termination Monitor. It stops the monitor and deletes the app state.
    /// - Note: This method must be called manually only or in the tests.
    /// This will reset the app state and the monitor will not able to detect Watchdog Termination due to absence of the previous app state.
    func flush() {
        stop()
    }
}

extension WatchdogTerminationMonitor: FeatureMessageReceiver {
    /// Receives the feature message and updates the app state based on the context message.
    /// It relies on `ApplicationStatePublisher` context message to update the app state.
    /// Other messages are ignored.
    /// - Parameters:
    ///   - message: The feature message.
    ///   - core: The core instance.
    /// - Returns: Always `false`, because it doesn't block the message propagation.
    func receive(message: DatadogInternal.FeatureMessage, from core: any DatadogInternal.DatadogCoreProtocol) -> Bool {
        guard case .context(let context) = message else {
            return false
        }

        if currentState == .initialized {
            guard let launchReport = context.additionalContext(ofType: LaunchReport.self) else {
                return false
            }

            self.start(launchReport: launchReport)
        }

        // Once the monitor has started, ie watchdog termination check has been done
        // we can start updating the app state based on the context message
        guard currentState == .started else {
            return false
        }

        let state = context.applicationStateHistory.currentState
        appStateManager.updateAppState(state: state)

        return false
    }
}
