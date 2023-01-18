/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation
import UIKit

/// An observer of `AppStateHistory` value.
internal typealias AppStateHistoryObserver = ValueObserver

/// Provides history of app foreground / background states.
internal protocol AppStateListening: AnyObject {
    /// Last published `AppStateHistory`.
    var history: AppStateHistory { get }

    /// Subscribers observer to be notified on `AppStateHistory` changes.
    func subscribe<Observer: AppStateHistoryObserver>(_ subscriber: Observer) where Observer.ObservedValue == AppStateHistory
}

internal class AppStateListener: AppStateListening {
    typealias Snapshot = AppStateHistory.Snapshot

    private let dateProvider: DateProvider
    private let publisher: ValuePublisher<AppStateHistory>
    /// The notification center where this listener observes following `UIApplication` notifications:
    /// - `.didBecomeActiveNotification`
    /// - `.willResignActiveNotification`
    /// - `.didEnterBackgroundNotification`
    /// - `.willEnterForegroundNotification`
    private weak var notificationCenter: NotificationCenter?

    var history: AppStateHistory {
        let current = publisher.currentValue
        return .init(
            initialSnapshot: current.initialSnapshot,
            recentDate: dateProvider.now,
            snapshots: current.snapshots
        )
    }

    convenience init(dateProvider: DateProvider) {
        self.init(
            dateProvider: dateProvider,
            initialAppState: UIApplication.managedShared?.applicationState ?? .active, // fallback to most expected state,
            notificationCenter: .default
        )
    }

    init(
        dateProvider: DateProvider,
        initialAppState: UIApplication.State,
        notificationCenter: NotificationCenter
    ) {
        let currentSnapshot = Snapshot(
            state: AppState(initialAppState),
            date: dateProvider.now
        )
        self.dateProvider = dateProvider
        self.notificationCenter = notificationCenter
        self.publisher = ValuePublisher(
            initialValue: AppStateHistory(
                initialSnapshot: currentSnapshot,
                recentDate: currentSnapshot.date
            )
        )

        notificationCenter.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    deinit {
        notificationCenter?.removeObserver(self, name: UIApplication.didBecomeActiveNotification, object: nil)
        notificationCenter?.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter?.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
        notificationCenter?.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
    }

    @objc
    private func appDidBecomeActive() {
        registerChange(to: .active)
    }

    @objc
    private func appWillResignActive() {
        registerChange(to: .inactive)
    }

    @objc
    private func appDidEnterBackground() {
        registerChange(to: .background)
    }

    @objc
    private func appWillEnterForeground() {
        registerChange(to: .inactive)
    }

    private func registerChange(to newState: AppState) {
        let now = dateProvider.now
        var value = publisher.currentValue
        value.append(Snapshot(state: newState, date: now))
        publisher.publishAsync(value)
    }

    // MARK: - Managing Subscribers

    func subscribe<Observer: AppStateHistoryObserver>(_ subscriber: Observer) where Observer.ObservedValue == AppStateHistory {
        publisher.subscribe(subscriber)
    }
}
