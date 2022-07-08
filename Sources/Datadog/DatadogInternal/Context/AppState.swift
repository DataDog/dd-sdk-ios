/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import Foundation

/// Application state.
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

    private(set) var initialSnapshot: Snapshot
    private(set) var snapshots: [Snapshot]

    /// Date of last the update to `AppStateHistory`.
    private(set) var recentDate: Date

    /// The most recent app state `Snapshot`.
    var currentSnapshot: Snapshot {
        return Snapshot(
            state: (snapshots.last ?? initialSnapshot).state,
            date: recentDate
        )
    }

    init(
        initialSnapshot: Snapshot,
        recentDate: Date,
        snapshots: [Snapshot] = []
    ) {
        self.initialSnapshot = initialSnapshot
        self.snapshots = snapshots
        self.recentDate = recentDate
    }

    /// Limits or extrapolates app state history to the given range
    /// This is useful when you record between 0...3t but you are concerned of t...2t only
    /// - Parameter range: if outside of initial and final states, it extrapolates; otherwise it limits
    /// - Returns: a history instance spanning the given range
    func take(between range: ClosedRange<Date>) -> AppStateHistory {
        .init(
            // move initial state to lowerBound
            initialSnapshot: Snapshot(
                state: state(at: range.lowerBound),
                date: range.lowerBound
            ),
            // move final state to upperBound
            recentDate: range.upperBound,
            // filter changes outside of the range
            snapshots: snapshots.filter { range.contains($0.date) }
        )
    }

    mutating func append(_ snapshot: Snapshot) {
        snapshots.append(snapshot)
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

#if canImport(UIKit)

import UIKit

extension AppState {
    init(_ state: UIApplication.State) {
        switch state {
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

#endif
