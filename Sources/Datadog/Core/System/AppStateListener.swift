/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation
import class UIKit.UIApplication

/// A data structure to represent recorded app states in a given period of time
internal struct AppStateHistory: Equatable {
    /// Snapshot of the app state at `date`
    struct Snapshot: Equatable {
        let isActive: Bool
        let date: Date
    }

    var initialState: Snapshot
    var changes = [Snapshot]()
    var finalDate: Date
    var finalState: Snapshot {
        return Snapshot(
            isActive: (changes.last ?? initialState).isActive,
            date: finalDate
        )
    }

    /// Limits or extrapolates app state history to the given range
    /// This is useful when you record between 0...3t but you are concerned of t...2t only
    /// - Parameter range: if outside of `initialState` and `finalState`, it extrapolates; otherwise it limits
    /// - Returns: a history instance spanning the given range
    func take(between range: ClosedRange<Date>) -> AppStateHistory {
        var taken = self
        // move initial state to lowerBound
        taken.initialState = Snapshot(
            isActive: isActive(at: range.lowerBound),
            date: range.lowerBound
        )
        // move final state to upperBound
        taken.finalDate = range.upperBound
        // filter changes outside of the range
        taken.changes = taken.changes.filter { range.contains($0.date) }
        return taken
    }

    var foregroundDuration: TimeInterval {
        var duration: TimeInterval = 0.0
        var lastActiveStartDate: Date?
        let allEvents = [initialState] + changes + [finalState]
        for event in allEvents {
            if let startDate = lastActiveStartDate {
                duration += event.date.timeIntervalSince(startDate)
            }
            if event.isActive {
                lastActiveStartDate = event.date
            } else {
                lastActiveStartDate = nil
            }
        }
        return duration
    }

    var didRunInBackground: Bool {
        return !initialState.isActive || !finalState.isActive
    }

    private func isActive(at date: Date) -> Bool {
        if date <= initialState.date {
            // we assume there was no change before initial state
            return initialState.isActive
        } else if finalState.date <= date {
            // and no change after final state
            return finalState.isActive
        }
        var active = initialState
        for change in changes {
            if date < change.date {
                break
            }
            active = change
        }
        return active.isActive
    }
}

internal protocol AppStateListening: AnyObject {
    var history: AppStateHistory { get }
}

internal class AppStateListener: AppStateListening {
    typealias Snapshot = AppStateHistory.Snapshot

    private let dateProvider: DateProvider
    private let publisher: ValuePublisher<AppStateHistory>

    var history: AppStateHistory {
        var current = publisher.currentValue
        current.finalDate = dateProvider.currentDate()
        return current
    }

    private static var isAppActive: Bool {
        return UIApplication.managedShared?.applicationState == .active
    }

    init(
        dateProvider: DateProvider,
        notificationCenter: NotificationCenter = .default
    ) {
        self.dateProvider = dateProvider
        let currentState = Snapshot(
            isActive: AppStateListener.isAppActive,
            date: dateProvider.currentDate()
        )
        self.publisher = ValuePublisher(
            initialValue: AppStateHistory(
                initialState: currentState,
                finalDate: currentState.date
            )
        )

        notificationCenter.addObserver(self, selector: #selector(appWillResignActive), name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appDidBecomeActive), name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    @objc
    private func appWillResignActive() {
        let now = dateProvider.currentDate()
        var value = publisher.currentValue
        value.changes.append(Snapshot(isActive: false, date: now))
        publisher.publishAsync(value)
    }
    @objc
    private func appDidBecomeActive() {
        let now = dateProvider.currentDate()
        var value = publisher.currentValue
        value.changes.append(Snapshot(isActive: true, date: now))
        publisher.publishAsync(value)
    }
}
