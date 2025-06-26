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

    /// The current application state history.
    ///
    /// **Note**: It must be accessed from the main thread.
    private var history: AppStateHistory

    /// The receiver for publishing the state history.
    @ReadWriteLock
    private var receiver: ContextValueReceiver<AppStateHistory>?

    /// Creates a Application state publisher for publishing application state
    /// history.
    ///
    /// **Note**: It must be called on the main thread.
    ///
    /// - Parameters:
    ///   - appStateHistory: The history of app state and their transitions over time.
    ///   - notificationCenter: The notification center where this publisher observes `UIApplication` notifications.
    ///   - dateProvider: The date provider for the Application state snapshot timestamp.
    ///   - queue: The queue for publishing the history.
    init(
        appStateHistory: AppStateHistory,
        notificationCenter: NotificationCenter,
        dateProvider: DateProvider
    ) {
        self.initialValue = appStateHistory
        self.history = initialValue
        self.dateProvider = dateProvider
        self.notificationCenter = notificationCenter
    }

    func publish(to receiver: @escaping ContextValueReceiver<AppStateHistory>) {
        // The `notificationCenter` must be subscribed to on the main thread to ensure a deterministic subscription order.
        // By synchronizing on the main thread, Core will always receive app state change notifications before Features,
        // even if Features implement their own subscriptions (Core is always enabled before Features).
        dd_assert(Thread.isMainThread, "Must be called on the main thread")

        self.receiver = receiver
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
        // This must run on the main thread for two reasons:
        // - For maximum performance, `history` is lock-free and relies on synchronization through a single thread.
        // - `receiver` must be updated from the main thread to ensure the new app state is always available
        //   for the next `eventWriteContext {}` and `context {}` request on this thread.
        dd_assert(Thread.isMainThread, "Must be called on main thread")
        history.append(state: state, at: dateProvider.now)
        receiver?(history)
    }

    func cancel() {
        notificationCenter.removeObserver(self, name: ApplicationNotifications.didBecomeActive, object: nil)
        notificationCenter.removeObserver(self, name: ApplicationNotifications.willResignActive, object: nil)
        notificationCenter.removeObserver(self, name: ApplicationNotifications.didEnterBackground, object: nil)
        notificationCenter.removeObserver(self, name: ApplicationNotifications.willEnterForeground, object: nil)
        receiver = nil
    }
}

#endif
