/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

#if canImport(AppKit)
import AppKit
import DatadogInternal

internal final class ApplicationStatePublisher: ContextValuePublisher {
    /// The initial history value.
    let initialValue: AppStateHistory

    /// The notification center where this publisher observes application notifications.
    ///
    /// This is usually `NotificationCenter.default`.
    private let applicationNotificationCenter: NotificationCenter

    /// The notification center where this publisher observes workspace notifications.
    ///
    /// This is usually `NSWorkspace.shared`.
    private let workspaceNotificationCenter: NotificationCenter

    /// The date provider for the Application state snapshot timestamp.
    private let dateProvider: DateProvider

    /// Provides app state information coming from system APIs.
    private let applicationStateProvider: MacOSApplicationStateProvider

    /// The current application state history.
    @MainActor private var history: AppStateHistory

    /// The receiver for publishing the state history.
    @ReadWriteLock
    private var receiver: ContextValueReceiver<AppStateHistory>?

    /// Notification centre where `NSApplication.*` notifications are posted.
    private var applicationObservers: [NSObjectProtocol] = []

    /// Notification centre where `NSWorkspace.*` notifications are posted.
    private var workspaceObservers: [NSObjectProtocol] = []

    /// `true` if the system is sleeping, `false` otherwise.
    ///
    /// This is `true` between receiving a `NSWorkspace.willSleepNotification` and `NSWorkspace.didWakeNotification`
    /// notifications. Technically the system will not be sleeping the entire time, since any process can delay sleep by 30 seconds after receiving
    /// the first notification, and the system wakes up slightly before receiving the second one. An edge case is if the user performs an operation
    /// that wakes up the system after `NSWorkspace.willSleepNotification` being posted, but before the system actually goes to sleep.
    /// However, there is no way to run code while the system is sleeping (as the CPU is off) so this will always be an approximation.
    @MainActor private var isSleeping: Bool = false

    /// `true` if the system is displaying the login window, `false` otherwise.
    ///
    /// The login window is displayed in many situations. The obvious ones are the lock screen, but it's also displayed (even
    /// if the login prompt is not visible) when the screen saver is active, during display or system sleep. This happens even
    /// if the system is configured to never ask for authentication after waking up.
    @MainActor private var isLoginWindowProcessActive: Bool

    /// Creates a Application state publisher for publishing application state
    /// history.
    ///
    /// **Note**: It must be called on the main thread.
    ///
    /// - Parameters:
    ///   - appStateHistory: The history of app state and their transitions over time.
    ///   - applicationNotificationCenter: The notification center where this publisher observes `NSApplication` notifications.
    ///   - workspaceNotificationCenter: The notification center where this publisher observes `NSWorkspace` notifications.
    ///   - applicationStateProvider: Provides app state information coming from system APIs.
    ///   - dateProvider: The date provider for the Application state snapshot timestamp.
    @MainActor
    init(
        appStateHistory: AppStateHistory,
        applicationNotificationCenter: NotificationCenter,
        workspaceNotificationCenter: NotificationCenter,
        applicationStateProvider: MacOSApplicationStateProvider,
        dateProvider: DateProvider
    ) {
        self.initialValue = appStateHistory
        self.history = initialValue
        self.dateProvider = dateProvider
        self.applicationNotificationCenter = applicationNotificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.applicationStateProvider = applicationStateProvider
        self.isLoginWindowProcessActive = applicationStateProvider.frontmostApplicationIsLoginWindow
    }

    func publish(to receiver: @escaping ContextValueReceiver<AppStateHistory>) {
        // The `notificationCenter` must be subscribed to on the main thread to ensure a deterministic subscription order.
        // By synchronizing on the main thread, Core will always receive app state change notifications before Features,
        // even if Features implement their own subscriptions (Core is always enabled before Features).
        dd_assert(Thread.isMainThread, "Must be called on the main thread")

        self.receiver = receiver

        applicationObservers.append(contentsOf: [
            addApplicationObserver(ApplicationNotifications.didBecomeActive),
            addApplicationObserver(ApplicationNotifications.didResignActive),
            addApplicationObserver(ApplicationNotifications.didHide),
            addApplicationObserver(ApplicationNotifications.didUnhide),
            addApplicationObserver(ApplicationNotifications.willTerminate) { [weak self] _ in
                self?.append(state: .terminating)
                return false
            }
        ])

        workspaceObservers.append(contentsOf: [
            addWorkspaceObserver(WorkspaceNotifications.didWake) { [weak self] _ in
                self?.isSleeping = false
                return true
            },
            addWorkspaceObserver(WorkspaceNotifications.willSleep) { [weak self] _ in
                self?.isSleeping = true
                return true
            },
            addWorkspaceObserver(WorkspaceNotifications.didActivateApplication, f: handleDidActivateApplication),
            addWorkspaceObserver(WorkspaceNotifications.didDeactivateApplication, f: handleDidDeactivateApplication),
        ])
    }

    /// Helper function for setting up and observer.
    ///
    /// Methods like `addWorkspaceObserver` and `addApplicationObserver` can pass an optional
    /// function that processes the notification before `updateState` is called.
    ///
    /// - Parameters:
    ///   - notification: The received notification.
    ///
    /// - Returns: `true` if `updateState` should be called after this function runs, `false` otherwise.
    private typealias ObserverAdditionalFunction = @MainActor (Notification) -> (Bool)?

    /// Adds an observer to the `workspaceNotificationCenter`.
    ///
    /// Convenience function for setting up a notification observer.
    ///
    /// - Parameters:
    ///   - notificationName: The name of the notification to listen to.
    ///   - f: An optional `ObserverAdditionalFunction` to run before `updateState`. If `f` returns `false`,
    ///   `updateState` it not called. Otherwise, if it returns `true` or `nil` is passed, `updateState` is called.
    private func addWorkspaceObserver(_ notificationName: Notification.Name, f: ObserverAdditionalFunction? = nil) -> NSObjectProtocol {
        add(notificationName, from: workspaceNotificationCenter, f: f)
    }

    /// Adds an observer to the `applicationNotificationCenter`.
    ///
    /// Convenience function for setting up a notification observer.
    ///
    /// - Parameters:
    ///   - notificationName: The name of the notification to listen to.
    ///   - f: An optional `ObserverAdditionalFunction` to run before `updateState`. If `f` returns `false`,
    ///  `updateState` it not called. Otherwise, if it returns `true` or `nil` is passed, `updateState` is called.
    private func addApplicationObserver(_ notificationName: Notification.Name, f: ObserverAdditionalFunction? = nil) -> NSObjectProtocol {
        add(notificationName, from: applicationNotificationCenter, f: f)
    }

    /// Adds an observer to the given notification center.
    ///
    /// Convenience function for setting up a notification observer.
    ///
    /// - Parameters:
    ///   - notificationName: The name of the notification to listen to.
    ///   - notificationCenter: The notification center where the observer should be registered in.
    ///   - f: An optional `ObserverAdditionalFunction` to run before `updateState`. If `f` returns `false`,
    ///   `updateState` it not called. Otherwise, if it returns `true` or `nil` is passed, `updateState` is called.
    private func add(_ notificationName: Notification.Name, from notificationCenter: NotificationCenter, f: ObserverAdditionalFunction? = nil) -> NSObjectProtocol {
        notificationCenter.addObserver(forName: notificationName, object: nil, queue: .main, using: { [weak self] note in
            MainActor.assumeIsolated {
                guard f?(note) != false else {
                    return
                }
                self?.updateState()
            }
        })
    }

    /// Called when a `NSWorkspace.didActivateApplicationNotification` is received.
    ///
    /// Check `ApplicationStatePublisher.handleWorkspaceActive(_:didBecomeActive:)`
    /// for more details.
    ///
    /// - Parameters:
    ///   -  note: The notification to handle.
    ///
    /// - Returns: `true` if the value of `isLoginWindowProcessActive` is changed, and thus `updateState` must be
    /// called, `false` otherwise.
    @MainActor
    private func handleDidActivateApplication(_ note: Notification) -> Bool {
        handleWorkspaceActive(note, didBecomeActive: true)
    }

    /// Called when a `NSWorkspace.didDeactivateApplicationNotification` is received.
    ///
    /// Check `ApplicationStatePublisher.handleWorkspaceActive(_:didBecomeActive:)`
    /// for more details.
    ///
    /// - Parameters:
    ///   -  note: The notification to handle.
    ///
    /// - Returns: `true` if the value of `isLoginWindowProcessActive` is changed, and thus `updateState` must be
    /// called, `false` otherwise.
    @MainActor
    private func handleDidDeactivateApplication(_ note: Notification) -> Bool {
        handleWorkspaceActive(note, didBecomeActive: false)
    }

    /// Called when a `NSWorkspace.didActivateApplicationNotification` or
    /// `NSWorkspace.didDeactivateApplicationNotification` is received.
    ///
    /// The only reliable way to know when the login window shows and hides is by listening to all notifications from `NSWorkspace`
    /// regarding application activation and deactivation (aka, applications coming to the foreground, or being sent into background).
    /// This function processes such notifications and if they refer to the login window process, it updates the value of
    /// `isLoginWindowProcessActive` and returns `true` signaling `updateState` must be called afterwards. Otherwise,
    /// if the notification referred to some other process, no updates are done, `false` is returned, and no further processing is required.
    ///
    /// - Parameters:
    ///   - note: The notification to handle.
    ///   - didBecomeActive: `true` if this was a `didActivateApplicationNotification` notification, false if it was
    ///   a `didDeactivateApplicationNotification`.
    ///
    /// - Returns: `true` if the value of `isLoginWindowProcessActive` is changed, and thus `updateState` must be
    /// called, `false` otherwise.
    @MainActor
    private func handleWorkspaceActive(_ note: Notification, didBecomeActive: Bool) -> Bool {
        guard let userInfo = note.userInfo,
              let app = userInfo[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.isLoginWindowProcess
        else {
            return false
        }

        isLoginWindowProcessActive = didBecomeActive
        return true
    }

    /// Updates the current `AppState` based on the variables representing the current system state regarding this application.
    @MainActor
    private func updateState() {
        guard history.currentState != .terminating else {
            return
        }

        if isSleeping {
            append(state: .sleeping)
        } else if isLoginWindowProcessActive {
            append(state: .lockScreen)
        } else if applicationStateProvider.isHidden {
            append(state: .hidden)
        } else {
            append(state: applicationStateProvider.isActive ? .active : .inactive)
        }
    }

    @MainActor
    private func append(state: AppState) {
        // This must run on the main thread for two reasons:
        // - For maximum performance, `history` is lock-free and relies on synchronization through a single thread.
        // - `receiver` must be updated from the main thread to ensure the new app state is always available
        //   for the next `eventWriteContext {}` and `context {}` request on this thread.
        history.append(state: state, at: dateProvider.now)
        receiver?(history)
    }

    func cancel() {
        applicationObservers.forEach { observer in
            applicationNotificationCenter.removeObserver(observer)
        }
        applicationObservers.removeAll()

        workspaceObservers.forEach { observer in
            workspaceNotificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        receiver = nil
    }
}

#endif
