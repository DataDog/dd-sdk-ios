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
        /// The monitor has started and is listening to the changes.
        case started
        /// The monitor is starting. It is still not listening to the changes.
        case starting
        /// The monitor has stopped and is not listening to the changes.
        case stopped
    }

    enum ErrorMessages {
        static let failedToCheckWatchdogTermination = "Failed to check if Watchdog Termination occurred"
        static let detectedWatchdogTermination = "Based on heuristics, previous app session was terminated by Watchdog"
        static let failedToReadViewEvent = "Failed to read the view event from the data store"
        static let rumViewEventUpdated = "RUM View event updated"
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
        self.currentState = .stopped
    }

    /// Starts the Watchdog Termination Monitor.
    /// - Parameter launchReport: The launch report containing information about the app launch (if available).
    func start(launchReport: LaunchReport) {
        guard currentState == .stopped else {
            return
        }

        currentState = .starting
        sendWatchTerminationIfFound(launch: launchReport) { [weak self] in
            self?.currentState = .started
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
        // The monitor state must be started to update the view event,
        // because saved view event might be currently used to report the Watchdog Termination event.
        guard currentState == .started else {
            return
        }

        DD.logger.debug(ErrorMessages.rumViewEventUpdated)
        feature.rumDataStore.setValue(viewEvent, forKey: .watchdogRUMViewEvent)
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

    /// Sends the Watchdog Termination event to Datadog with the given state.
    /// Because Watchdog Termination are reported in the next app session, it uses the saved `RUMViewEvent`
    /// to report the event.
    /// - Parameter state: The app state when the Watchdog Termination occurred.
    private func sendWatchTermination(state: AppStateInfo, completion: @escaping () -> Void) {
        feature.context { [weak self] context in
            do {
                let likelyCrashedAt = try self?.storage?.mostRecentModifiedFileAt(before: context.launchInfo.processLaunchDate)
                self?.feature.rumDataStore.value(forKey: .watchdogRUMViewEvent) { [weak self] (viewEvent: RUMViewEvent?) in
                    guard let viewEvent = viewEvent else {
                        DD.logger.error(ErrorMessages.failedToReadViewEvent)
                        self?.feature.telemetry.error(ErrorMessages.failedToReadViewEvent)
                        completion()
                        return
                    }
                    self?.reporter.send(date: likelyCrashedAt, state: state, viewEvent: viewEvent)
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
        currentState = .stopped
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

        if currentState == .stopped {
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
