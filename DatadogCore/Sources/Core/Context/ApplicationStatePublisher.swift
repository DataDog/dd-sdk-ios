/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(UIKit)
import UIKit
import DatadogInternal
#if canImport(WatchKit)
import WatchKit
#endif

internal final class ApplicationStatePublisher: ContextValuePublisher {
    typealias Snapshot = AppStateHistory.Snapshot

    /// The default publisher queue.
    private static let defaultQueue = DispatchQueue(
        label: "com.datadoghq.app-state-publisher",
        target: .global(qos: .utility)
    )

    /// The initial history value.
    let initialValue: AppStateHistory

    /// The notification center where this publisher observes following `UIApplication` notifications:
    /// - `.didBecomeActiveNotification`
    /// - `.willResignActiveNotification`
    /// - `.didEnterBackgroundNotification`
    /// - `.willEnterForegroundNotification`
    private let notificationCenter: NotificationCenter

    /// The date provider for the Application state snapshot timestamp.
    private let dateProvider: DateProvider

    /// The queue used to serialise access to the `history` and
    /// to publish the new history.
    private let queue: DispatchQueue

    /// The current application state history.
    ///
    /// To mutate in the `queue` only.
    private var history: AppStateHistory

    /// The receiver for publishing the state history.
    ///
    /// To mutate in the `queue` only.
    private var receiver: ContextValueReceiver<AppStateHistory>?

    /// Creates a Application state publisher for publishing application state
    /// history.
    ///
    /// **Note**: It must be called on the main thread.
    ///
    /// - Parameters:
    ///   - appStateProvider: The provider to access the current application state.
    ///   - notificationCenter: The notification center where this publisher observes `UIApplication` notifications.
    ///   - dateProvider: The date provider for the Application state snapshot timestamp.
    ///   - queue: The queue for publishing the history.
    init(
        appStateProvider: AppStateProvider,
        notificationCenter: NotificationCenter,
        dateProvider: DateProvider,
        queue: DispatchQueue = ApplicationStatePublisher.defaultQueue
    ) {
        let initialValue = AppStateHistory(
            initialState: appStateProvider.current,
            date: dateProvider.now
        )

        self.initialValue = initialValue
        self.history = initialValue
        self.queue = queue
        self.dateProvider = dateProvider
        self.notificationCenter = notificationCenter
    }

    func publish(to receiver: @escaping ContextValueReceiver<AppStateHistory>) {
        queue.async { self.receiver = receiver }
        notificationCenter.addObserver(self, selector: #selector(applicationDidBecomeActive), name: ApplicationNotifications.didBecomeActive, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationWillResignActive), name: ApplicationNotifications.willResignActive, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationDidEnterBackground), name: ApplicationNotifications.didEnterBackground, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationWillEnterForeground), name: ApplicationNotifications.willEnterForeground, object: nil)
    }

    @objc
    private func applicationDidBecomeActive() {
        append(state: .active)
    }

    @objc
    private func applicationWillResignActive() {
        append(state: .inactive)
    }

    @objc
    private func applicationDidEnterBackground() {
        append(state: .background)
    }

    @objc
    private func applicationWillEnterForeground() {
        append(state: .inactive)
    }

    private func append(state: AppState) {
        let snapshot = Snapshot(state: state, date: dateProvider.now)
        queue.async {
            self.history.append(snapshot)
            self.receiver?(self.history)
        }
    }

    func cancel() {
        notificationCenter.removeObserver(self, name: ApplicationNotifications.didBecomeActive, object: nil)
        notificationCenter.removeObserver(self, name: ApplicationNotifications.willResignActive, object: nil)
        notificationCenter.removeObserver(self, name: ApplicationNotifications.didEnterBackground, object: nil)
        notificationCenter.removeObserver(self, name: ApplicationNotifications.willEnterForeground, object: nil)
        queue.async { self.receiver = nil }
    }
}

#endif
