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

/// Produces `AppStateHistory` updates via `AsyncStream` by observing UIApplication
/// lifecycle notifications.
///
/// The source maintains a running `AppStateHistory` and yields the latest snapshot
/// each time a lifecycle notification fires.
///
/// **Note:** Must be created on the main thread (UIKit requirement).
internal final class ApplicationStateSource: ContextValueSource, @unchecked Sendable {
    let initialValue: AppStateHistory
    let values: AsyncStream<AppStateHistory>

    private var history: AppStateHistory
    private let dateProvider: DateProvider
    private let notificationCenter: NotificationCenter
    private var observers: [Any] = []
    private var continuation: AsyncStream<AppStateHistory>.Continuation?

    init(
        appStateHistory: AppStateHistory,
        notificationCenter: NotificationCenter,
        dateProvider: DateProvider
    ) {
        dd_assert(Thread.isMainThread, "Must be called on the main thread")

        self.initialValue = appStateHistory
        self.history = appStateHistory
        self.dateProvider = dateProvider
        self.notificationCenter = notificationCenter

        var continuation: AsyncStream<AppStateHistory>.Continuation!
        self.values = AsyncStream { continuation = $0 }
        self.continuation = continuation

        // The `notificationCenter` must be subscribed to on the main thread to ensure a deterministic subscription order.
        // By synchronizing on the main thread, Core will always receive app state change notifications before Features,
        // even if Features implement their own subscriptions (Core is always enabled before Features).
        observers = [
            notificationCenter.addObserver(forName: ApplicationNotifications.didBecomeActive, object: nil, queue: .main) { [weak self] _ in
                self?.append(state: .active)
            },
            notificationCenter.addObserver(forName: ApplicationNotifications.willResignActive, object: nil, queue: .main) { [weak self] _ in
                self?.append(state: .inactive)
            },
            notificationCenter.addObserver(forName: ApplicationNotifications.didEnterBackground, object: nil, queue: .main) { [weak self] _ in
                self?.append(state: .background)
            },
            notificationCenter.addObserver(forName: ApplicationNotifications.willEnterForeground, object: nil, queue: .main) { [weak self] _ in
                self?.append(state: .inactive)
            }
        ]
    }

    deinit {
        observers.forEach { notificationCenter.removeObserver($0) }
        continuation?.finish()
    }

    private func append(state: AppState) {
        // This must run on the main thread for two reasons:
        // - For maximum performance, `history` is lock-free and relies on synchronization through a single thread.
        // - Updates must happen on the main thread to ensure the new app state is always available
        //   for the next `eventWriteContext {}` and `context {}` request on this thread.
        dd_assert(Thread.isMainThread, "Must be called on main thread")
        history.append(state: state, at: dateProvider.now)
        continuation?.yield(history)
    }
}

#endif
