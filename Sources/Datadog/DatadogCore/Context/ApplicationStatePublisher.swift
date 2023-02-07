/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(UIKit)
import UIKit
import DatadogInternal

internal final class ApplicationStatePublisher: ContextValuePublisher {
    typealias Snapshot = AppStateHistory.Snapshot

    private static var currentApplicationState: UIApplication.State {
        UIApplication.managedShared?.applicationState ?? .active // fallback to most expected state
    }

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
    /// - Parameters:
    ///   - initialState: The initial application state.
    ///   - queue: The queue for publishing the history.
    ///   - dateProvider: The date provider for the Application state snapshot timestamp.
    ///   - notificationCenter: The notification center where this publisher observes `UIApplication` notifications.
    init(
        initialState: AppState,
        queue: DispatchQueue = ApplicationStatePublisher.defaultQueue,
        dateProvider: DateProvider = SystemDateProvider(),
        notificationCenter: NotificationCenter = .default
    ) {
        let initialValue = AppStateHistory(
            initialState: initialState,
            date: dateProvider.now
        )

        self.initialValue = initialValue
        self.history = initialValue
        self.queue = queue
        self.dateProvider = dateProvider
        self.notificationCenter = notificationCenter
    }

    /// Creates a Application state publisher for publishing application state
    /// history.
    ///
    /// **Note**: It must be called on the main thread.
    ///
    /// - Parameters:
    ///   - applicationState: The current shared `UIApplication` state.
    ///   - queue: The queue for publishing the history.
    ///   - dateProvider: The date provider for the Application state snapshot timestamp.
    ///   - notificationCenter: The notification center where this publisher observes `UIApplication` notifications.
    convenience init(
        applicationState: UIApplication.State = ApplicationStatePublisher.currentApplicationState,
        queue: DispatchQueue = ApplicationStatePublisher.defaultQueue,
        dateProvider: DateProvider = SystemDateProvider(),
        notificationCenter: NotificationCenter = .default
    ) {
        self.init(
            initialState: AppState(applicationState),
            queue: queue,
            dateProvider: dateProvider,
            notificationCenter: notificationCenter
        )
    }

    func publish(to receiver: @escaping ContextValueReceiver<AppStateHistory>) {
        queue.async { self.receiver = receiver }
        notificationCenter.addObserver(self, selector: #selector(applicationDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(applicationWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
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
        notificationCenter.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        notificationCenter.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        queue.async { self.receiver = nil }
    }
}

#endif
