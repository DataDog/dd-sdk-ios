/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import Foundation

/// A protocol that provides access to the current application state.
///
/// This is used only at the SDK initialization. State changes during the SDK instance lifetime are tracked
/// by `DatadogCore.ApplicationStatePublisher`.
public protocol AppStateProvider: Sendable {
    /// The current application state.
    @MainActor var current: AppState { get }
}

public protocol AppStateProtocol: Codable {
    /// `true` if the application execution may be suspended in this state, `false` otherwise.
    ///
    /// This method's name uses the word "may" since it's not guaranteed the application is suspended just for being
    /// in one of the suspension-prone states. Returning `true` from here means the application may be suspended
    /// at any point while it remains on this state. In fact, if this method returns something, it means the application cannot
    /// be suspended, otherwise it would not be executing at all.
    ///
    /// On macOS, the only state when the application process stops running is during the device's sleep stages. Note this
    /// does not include the STOP/CONT UNIX signal handling. These signals are not catchable, and applications don't know
    /// they are about to be suspended, or have been resumed, using these signals.
    ///
    /// On iOS, the application may be suspended while it's in the background state. The OS may switch between suspended
    /// and background states allowing the application to perform background tasks.
    ///
    /// On all operating systems, the terminating/terminated states are not considered suspended, since on those states
    /// the application is indeed given CPU time to perform house-cleaning routines before being effectively terminated.
    var applicationMayBeSuspended: Bool { get }

    /// If the app is running in the foreground - no matter if receiving events or not (i.e. being interrupted because of transitioning from background).
    var isRunningInForeground: Bool { get }
}

#if os(macOS)
/// Application state.
public enum AppState: AppStateProtocol {
    /// The app is running in the foreground and currently receiving events.
    case active
    /// The app is in the background, or in the foreground but blocked by an interruption like a system dialog (for example,
    /// the shutdown confirmation dialog).
    case inactive
    /// The app is hidden (using the Hide command in Finder).
    case hidden
    /// The lock screen is active, and the Mac is **not** sleeping.
    /// This happens in multiple situations, like displays sleeping, lock screen, or screen saver turned on.
    /// Note the lock screen being active does not mean a password will be asked. That depends on the system configuration.
    case lockScreen
    /// The system is entering the sleep state, or sleeping.
    /// After receiving a `NSWorkspace.willSleepNotification`, processes can delay sleeping for 30 seconds. We have no way of
    /// knowing exactly when the process enters sleep by definition, as the CPU powers off and processes aren't running, so we assume sleep
    /// as soon as we get the notification.
    case sleeping
    /// The app is going through its shutdown sequence.
    case terminating

    public var applicationMayBeSuspended: Bool {
        switch self {
        case .sleeping: true
        case .active, .inactive, .hidden, .lockScreen, .terminating: false
        }
    }

    /// macOS does not have the same background concept as iOS.
    /// For the purposes of this method, it should always be true.
    public var isRunningInForeground: Bool {
        true
    }
}
#else
/// Application state.
public enum AppState: AppStateProtocol {
    /// The app is running in the foreground and currently receiving events.
    case active
    /// The app is running in the foreground but is not receiving events.
    /// This might happen as a result of an interruption or because the app is transitioning to or from the background.
    case inactive
    /// The app is running in the background.
    case background
    /// The app is terminated.
    case terminated

    public var applicationMayBeSuspended: Bool {
        switch self {
        case .background:
            return true
        case .active, .inactive, .terminated:
            return false
        }
    }

    public var isRunningInForeground: Bool {
        switch self {
        case .active, .inactive:
            return true
        case .background, .terminated:
            return false
        }
    }
}
#endif

/// Records app state transitions over time.
public struct AppStateHistory: Codable, Equatable {
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
        duration(during: range, predicate: { $0.isRunningInForeground })
    }

    /// Computes the total duration the app was running in states where the process could not have been suspended within the given time range.
    ///
    /// - Parameter range: The time period to analyze.
    /// - Returns: The total time (in seconds) spent in states the process could not have been suspended.
    public func applicationNotSuspendedDuration(during range: ClosedRange<Date>) -> TimeInterval {
        duration(during: range, predicate: { $0.applicationMayBeSuspended == false })
    }

    /// Helper function for calculating durations of a given condition.
    ///
    /// - Parameters:
    ///   - range: The time period to analyze.
    ///   - predicate: The predicate applied to each state in the history inside the given range. If `true` the duration of that
    ///   state is considered.
    /// - Returns: The total time (in seconds) spent in states that satisfy the predicate.
    private func duration(during range: ClosedRange<Date>, predicate: (AppState) -> Bool) -> TimeInterval {
        var total: TimeInterval = 0
        iterateStates(in: range) { state, duration in
            if predicate(state) {
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
