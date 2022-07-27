/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import class UIKit.UIApplication

/// Application state, constructed from `UIApplication.State`.
internal enum AppState: Equatable {
    /// The app is running in the foreground and currently receiving events.
    case active
    /// The app is running in the foreground but is not receiving events.
    /// This might happen as a result of an interruption or because the app is transitioning to or from the background.
    case inactive
    /// The app is running in the background.
    case background

    /// If the app is running in the foreground - no matter if receiving events or not (i.e. being interrupted because of transitioning from background).
    var isRunningInForeground: Bool {
        switch self {
        case .active, .inactive:
            return true
        case .background:
            return false
        }
    }

    init(uiApplicationState: UIApplication.State) {
        switch uiApplicationState {
        case .active:
            self = .active
        case .inactive:
            self = .inactive
        case .background:
            self = .background
        @unknown default:
            self = .active // in case a new state is introduced, we rather want to fallback to most expected state
        }
    }
}

/// A data structure to represent recorded app states in a given period of time
internal struct AppStateHistory: Equatable {
    /// Snapshot of the app state at `date`
    struct Snapshot: Equatable {
        /// The app state at this `date`.
        let state: AppState
        /// Date of recording this snapshot.
        let date: Date
    }

    fileprivate(set) var initialSnapshot: Snapshot
    fileprivate(set) var snapshots = [Snapshot]()

    /// Date of last the update to `AppStateHistory`.
    fileprivate(set) var recentDate: Date

    /// The most recent app state `Snapshot`.
    var currentSnapshot: Snapshot {
        return Snapshot(
            state: (snapshots.last ?? initialSnapshot).state,
            date: recentDate
        )
    }

    /// Limits or extrapolates app state history to the given range
    /// This is useful when you record between 0...3t but you are concerned of t...2t only
    /// - Parameter range: if outside of initial and final states, it extrapolates; otherwise it limits
    /// - Returns: a history instance spanning the given range
    func take(between range: ClosedRange<Date>) -> AppStateHistory {
        var taken = self
        // move initial state to lowerBound
        taken.initialSnapshot = Snapshot(
            state: state(at: range.lowerBound),
            date: range.lowerBound
        )
        // move final state to upperBound
        taken.recentDate = range.upperBound
        // filter changes outside of the range
        taken.snapshots = taken.snapshots.filter { range.contains($0.date) }
        return taken
    }

    var foregroundDuration: TimeInterval {
        var duration: TimeInterval = 0.0
        var lastActiveStartDate: Date?
        let allEvents = [initialSnapshot] + snapshots + [currentSnapshot]
        for event in allEvents {
            if let startDate = lastActiveStartDate {
                duration += event.date.timeIntervalSince(startDate)
            }
            if event.state.isRunningInForeground {
                lastActiveStartDate = event.date
            } else {
                lastActiveStartDate = nil
            }
        }
        return duration
    }

    private func state(at date: Date) -> AppState {
        if date <= initialSnapshot.date {
            // we assume there was no change before initial state
            return initialSnapshot.state
        } else if currentSnapshot.date <= date {
            // and no change after final state
            return currentSnapshot.state
        }
        var active = initialSnapshot
        for change in snapshots {
            if date < change.date {
                break
            }
            active = change
        }
        return active.state
    }
}

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
        var current = publisher.currentValue
        current.recentDate = dateProvider.now
        return current
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
            state: AppState(uiApplicationState: initialAppState),
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
        value.snapshots.append(Snapshot(state: newState, date: now))
        publisher.publishAsync(value)
    }

    // MARK: - Managing Subscribers

    func subscribe<Observer: AppStateHistoryObserver>(_ subscriber: Observer) where Observer.ObservedValue == AppStateHistory {
        publisher.subscribe(subscriber)
    }
}
