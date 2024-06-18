/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// Application state.
public enum AppState: Codable, PassthroughAnyCodable {
    /// The app is running in the foreground and currently receiving events.
    case active
    /// The app is running in the foreground but is not receiving events.
    /// This might happen as a result of an interruption or because the app is transitioning to or from the background.
    case inactive
    /// The app is running in the background.
    case background
    /// The app is terminated.
    case terminated

    /// If the app is running in the foreground - no matter if receiving events or not (i.e. being interrupted because of transitioning from background).
    public var isRunningInForeground: Bool {
        switch self {
        case .active, .inactive:
            return true
        case .background, .terminated:
            return false
        }
    }
}

/// A data structure to represent recorded app states in a given period of time
public struct AppStateHistory: Codable, Equatable, PassthroughAnyCodable {
    /// Snapshot of the app state at `date`
    public struct Snapshot: Codable, Equatable {
        /// The app state at this `date`.
        public let state: AppState
        /// Date of recording this snapshot.
        public let date: Date

        public init(state: AppState, date: Date) {
            self.state = state
            self.date = date
        }
    }

    public private(set) var initialSnapshot: Snapshot
    public private(set) var snapshots: [Snapshot]

    /// Date of the last update to `AppStateHistory`.
    public private(set) var recentDate: Date

    /// The most recent app state `Snapshot`.
    public var currentSnapshot: Snapshot {
        return Snapshot(
            state: (snapshots.last ?? initialSnapshot).state,
            date: recentDate
        )
    }

    public init(
        initialSnapshot: Snapshot,
        recentDate: Date,
        snapshots: [Snapshot] = []
    ) {
        self.initialSnapshot = initialSnapshot
        self.snapshots = snapshots
        self.recentDate = recentDate
    }

    public init(
        initialState: AppState,
        date: Date,
        snapshots: [Snapshot] = []
    ) {
        self.init(
            initialSnapshot: .init(state: initialState, date: date),
            recentDate: date,
            snapshots: snapshots
        )
    }

    /// Limits or extrapolates app state history to the given range
    /// This is useful when you record between 0...3t but you are concerned of t...2t only
    /// - Parameter range: if outside of initial and final states, it extrapolates; otherwise it limits
    /// - Returns: a history instance spanning the given range
    public func take(between range: ClosedRange<Date>) -> AppStateHistory {
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

    public mutating func append(_ snapshot: Snapshot) {
        snapshots.append(snapshot)
    }

    public var foregroundDuration: TimeInterval {
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
        for snapshot in snapshots.reversed() {
            if snapshot.date > date {
                continue
            }

            return snapshot.state
        }

        // we assume there was no change before initial state
        return initialSnapshot.state
    }
}

extension AppStateHistory {
    /// Return a history with an active initial state.
    ///
    /// - Parameter date: The date since the application is considred active.
    public static func active(since date: Date) -> AppStateHistory {
        .init(initialState: .active, date: date)
    }
}

#if canImport(UIKit)

import UIKit

extension AppState {
    public init(_ state: UIApplication.State) {
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
