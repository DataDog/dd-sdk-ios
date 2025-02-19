/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A protocol that provides access to the current application state.
/// See: https://developer.apple.com/documentation/uikit/uiapplication/state
public protocol AppStateProvider: Sendable {
    /// The current application state.
    ///
    /// **Note**: Must be called on the main thread.
    var current: AppState { get }
}

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

/// Records app state transitions over time.
public struct AppStateHistory: Codable, Equatable, PassthroughAnyCodable {
    /// A snapshot representing the app state at a specific point in time.
    private struct Snapshot: Codable, Equatable {
        let state: AppState
        let date: Date
    }

    /// The initial state of the app when this history instance was created.
    public let initialState: AppState
    /// A chronologically ordered list of app state snapshots. It includes the `initialState`.
    private var snapshots: [Snapshot]
    /// The most recent recorded app state.
    public var currentState: AppState { snapshots.last?.state ?? initialState }

    /// Creates a new `AppStateHistory` with an initial state.
    ///
    /// - Parameters:
    ///   - initialState: The starting `AppState` of the app.
    ///   - date: The timestamp when the initial state was recorded.
    public init(initialState: AppState, date: Date) {
        let initialSnapshot = Snapshot(state: initialState, date: date)
        self.initialState = initialState
        self.snapshots = [initialSnapshot]
    }

    /// Appends a new app state transition to the history.
    ///
    /// - Parameters:
    ///   - state: The new `AppState` to be recorded.
    ///   - date: The timestamp when the state transition occurred.
    ///
    /// It is optimised for monothonic dates. If the provided `date` is earlier than one for an existing state, then states are re-sorted to maintain chronological order.
    public mutating func append(state: AppState, at date: Date) {
        let lastSnapshotDate = snapshots.last?.date ?? .distantPast
        let newSnapshot = Snapshot(state: state, date: date)
        snapshots.append(newSnapshot)

        if newSnapshot.date < lastSnapshotDate {
            // Ensure snapshots remain chronologically ordered.
            // Under normal conditions, this should never be needed, as app state
            // transitions are tracked based on real-time system events.
            snapshots.sort { $0.date < $1.date }
        }
    }

    /// Returns the app state at a specific point in time, if available.
    ///
    /// - Parameter date: The timestamp for which to retrieve the app state.
    /// - Returns: The `AppState` that was active at the given time, or `nil` if `date`
    ///   is earlier than the date of initial state.
    public func state(at date: Date) -> AppState? {
        // Iterate in reverse order, as recent states are more likely to match.
        let snapshot = snapshots.reversed().first { $0.date <= date }
        return snapshot?.state
    }

    /// Checks whether the app was in a specific state within the given time range.
    ///
    /// - Parameters:
    ///   - range: The time period to check.
    ///   - predicate: A closure that evaluates whether a given `AppState` matches the desired condition.
    /// - Returns: `true` if any state within `range` satisfies the predicate, otherwise `false`.
    public func containsState(during range: ClosedRange<Date>, where predicate: (AppState) -> Bool) -> Bool {
        var contains = false
        iterateStates(in: range) { state, _ in
            contains = contains || predicate(state)
        }
        return contains
    }

    /// Computes the total duration the app was running in the foreground within the given time range.
    ///
    /// - Parameter range: The time period to analyze.
    /// - Returns: The total time (in seconds) spent in foreground states.
    public func foregroundDuration(during range: ClosedRange<Date>) -> TimeInterval {
        var total: TimeInterval = 0
        iterateStates(in: range) { state, duration in
            if state.isRunningInForeground {
                total += duration
            }
        }
        return total
    }

    /// Iterates through states and their intervals within a specified time range.
    ///   - If a snapshot **falls entirely outside** the range, it is ignored.
    ///   - If a snapshot **extends beyond `range.upperBound`**, it is clamped to `range.upperBound`.
    ///   - If a snapshot **starts before `range.lowerBound`**, it is not clamped.
    ///
    /// - Parameters:
    ///   - range: The time range to analyze states in.
    ///   - iterator: A closure that receives each `AppState` and its associated duration, clamped to the provided `range`.
    private func iterateStates(in range: ClosedRange<Date>, perform iterator: (AppState, TimeInterval) -> Void) {
        let finalState = snapshots.last?.state ?? initialState
        let finalSnapshot = Snapshot(state: finalState, date: .distantFuture)
        let allSnapshots = snapshots + [finalSnapshot]

        for (current, next) in zip(allSnapshots, allSnapshots.dropFirst()) {
            let start = max(current.date, range.lowerBound)
            let end = min(next.date, range.upperBound)
            if end > start {
                let duration = end.timeIntervalSince(start)
                iterator(current.state, duration)
            }
        }
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

#if canImport(WatchKit)

import WatchKit

public struct DefaultAppStateProvider: AppStateProvider {
    public init() {}

    /// Gets the current application state.
    ///
    /// **Note**: Must be called on the main thread.
    public var current: AppState {
        let wkState = WKExtension.dd.shared.applicationState
        return AppState(wkState)
    }
}

extension AppState {
    public init(_ state: WKApplicationState) {
        switch state {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        @unknown default:
            self = .active // in case a new state is introduced, default to most expected state
        }
    }
}

#elseif canImport(UIKit)

import UIKit

public struct DefaultAppStateProvider: AppStateProvider {
    public init() {}

    /// Gets the current application state.
    ///
    /// **Note**: Must be called on the main thread.
    public var current: AppState {
        let uiKitState = UIApplication.dd.managedShared?.applicationState ?? .active // fallback to most expected state
        return AppState(uiKitState)
    }
}

extension AppState {
    public init(_ state: UIApplication.State) {
        switch state {
        case .active: self = .active
        case .inactive: self = .inactive
        case .background: self = .background
        @unknown default: self = .active // in case a new state is introduced, default to most expected state
        }
    }
}

#else // macOS (no UIKit and no WatchKit)

public struct DefaultAppStateProvider: AppStateProvider {
    public init() {}
    public let current: AppState = .active
}

#endif
