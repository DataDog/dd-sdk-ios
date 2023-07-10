/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal

class AppStateHistoryTests: XCTestCase {
    func testItBuildsAppStateFromUIApplicationState() {
        XCTAssertEqual(AppState(.active), .active)
        XCTAssertEqual(AppState(.inactive), .inactive)
        XCTAssertEqual(AppState(.background), .background)
    }

    func testWhenAppTransitionsBetweenForegroundAndBackground_itComputesTotalForegroundDuration() {
        let numberOfForegroundSnapshots: Int = .mockRandom(min: 0, max: 20)
        let numberOfBackgroundSnapshots: Int = .mockRandom(min: numberOfForegroundSnapshots == 0 ? 1 : 0, max: 20) // must include at least one snapshot
        let numberOfSnapshots = numberOfForegroundSnapshots + numberOfBackgroundSnapshots
        let snapshotDuration: TimeInterval = .mockRandom(min: 0.1, max: 5)

        // Given
        let date: Date = .mockRandomInThePast()
        let snapshotDates: [Date] = (0..<numberOfSnapshots).shuffled()
            .map { idx in date.addingTimeInterval(TimeInterval(idx) * snapshotDuration) }
        let foregroundSnapshots = snapshotDates.dropLast(numberOfBackgroundSnapshots)
            .map { AppStateHistory.Snapshot(state: .mockRandom(runningInForeground: true), date: $0) }
        let backgroundSnapshots = snapshotDates.dropFirst(numberOfForegroundSnapshots)
            .map { AppStateHistory.Snapshot(state: .mockRandom(runningInForeground: false), date: $0) }

        // When
        let allSnapshots = (foregroundSnapshots + backgroundSnapshots).sorted { $0.date < $1.date }
        let totalDuration = TimeInterval(numberOfSnapshots) * snapshotDuration

        let history = AppStateHistory(
            initialSnapshot: allSnapshots[0],
            recentDate: date.addingTimeInterval(totalDuration),
            snapshots: Array(allSnapshots.dropFirst())
        )

        // Then
        let expectedForegroundDuration = TimeInterval(numberOfForegroundSnapshots) * snapshotDuration
        XCTAssertEqual(history.foregroundDuration, expectedForegroundDuration, accuracy: 0.01)
    }

    func testExtrapolation() {
        let randomAppState: AppState = .mockRandom()
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let history = AppStateHistory(
            initialSnapshot: .init(state: randomAppState, date: startDate),
            recentDate: startDate + 5.0,
            snapshots: []
        )
        let extrapolatedHistory = history.take(
            between: (startDate - 5.0)...(startDate + 15.0)
        )

        let expectedHistory = AppStateHistory(
            initialSnapshot: .init(state: randomAppState, date: startDate - 5.0),
            recentDate: startDate + 15.0,
            snapshots: []
        )
        XCTAssertEqual(extrapolatedHistory, expectedHistory)
    }

    func testLimiting() {
        let randomAppState: AppState = .mockRandom()
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let history = AppStateHistory(
            initialSnapshot: .init(state: randomAppState, date: startDate),
            recentDate: startDate + 20.0,
            snapshots: []
        )
        let limitedHistory = history.take(
            between: (startDate + 5.0)...(startDate + 10.0)
        )

        let expectedHistory = AppStateHistory(
            initialSnapshot: .init(state: randomAppState, date: startDate + 5.0),
            recentDate: startDate + 10.0,
            snapshots: []
        )
        XCTAssertEqual(limitedHistory, expectedHistory)
    }

    func testLimitingWithChanges() {
        let randomFirstAppState: AppState = .mockRandom()
        let randomLastAppState: AppState = .mockRandom()

        let startDate = Date(timeIntervalSinceReferenceDate: 0.0)
        let firstChanges = (0...100).map { _ in
            AppStateHistory.Snapshot(
                state: randomFirstAppState,
                date: startDate + TimeInterval.random(in: 1...1_000)
            )
        }
        let lastChanges = (0...100).map { _ in
            AppStateHistory.Snapshot(
                state: randomLastAppState,
                date: startDate + TimeInterval.random(in: 2_000...3_000)
            )
        }
        var allChanges = (firstChanges + lastChanges)
        allChanges.append(.init(state: randomFirstAppState, date: startDate + 1_200))
        allChanges.append(.init(state: randomLastAppState, date: startDate + 1_500))
        allChanges.sort { $0.date < $1.date }
        let history = AppStateHistory(
            initialSnapshot: .init(state: randomFirstAppState, date: startDate),
            recentDate: startDate + 4_000,
            snapshots: allChanges
        )

        let limitedHistory = history.take(
            between: (startDate + 1_250)...(startDate + 1_750)
        )

        let expectedHistory = AppStateHistory(
            initialSnapshot: .init(state: randomFirstAppState, date: startDate + 1_250),
            recentDate: startDate + 1_750,
            snapshots: [.init(state: randomLastAppState, date: startDate + 1_500)]
        )
        XCTAssertEqual(limitedHistory, expectedHistory)
    }
}
