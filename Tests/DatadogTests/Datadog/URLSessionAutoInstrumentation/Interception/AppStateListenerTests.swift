/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-2020 Datadog, Inc.
 */

import XCTest
@testable import Datadog

class AppStateHistoryTests: XCTestCase {
    func testForegroundDurationWithoutChanges() {
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let history = AppStateHistory(
            initialState: .init(isActive: true, date: startDate),
            changes: [],
            finalDate: startDate + 1.0
        )

        XCTAssertEqual(history.foregroundDuration, 1.0)
    }

    func testForegroundDuration() {
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let history = AppStateHistory(
            initialState: .init(isActive: true, date: startDate),
            changes: [
                .init(isActive: false, date: startDate + 1.0),
                .init(isActive: true, date: startDate + 2.0),
                .init(isActive: false, date: startDate + 3.0),
                .init(isActive: true, date: startDate + 4.0)
            ],
            finalDate: startDate + 5.0
        )

        XCTAssertEqual(history.foregroundDuration, 3.0)
    }

    func testForegroundDurationWithMissingChange() {
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let history = AppStateHistory(
            initialState: .init(isActive: true, date: startDate),
            changes: [
                .init(isActive: false, date: startDate + 1.0),
                .init(isActive: false, date: startDate + 3.0)
            ],
            finalDate: startDate + 5.0
        )

        XCTAssertEqual(history.foregroundDuration, 1.0)
    }

    func testExtrapolation() {
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let history = AppStateHistory(
            initialState: .init(isActive: true, date: startDate),
            changes: [],
            finalDate: startDate + 5.0
        )
        let extrapolatedHistory = history.take(
            between: (startDate - 5.0)...(startDate + 15.0)
        )

        let expectedHistory = AppStateHistory(
            initialState: .init(isActive: true, date: startDate - 5.0),
            changes: [],
            finalDate: startDate + 15.0
        )
        XCTAssertEqual(extrapolatedHistory, expectedHistory)
    }

    func testLimiting() {
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let history = AppStateHistory(
            initialState: .init(isActive: true, date: startDate),
            changes: [],
            finalDate: startDate + 20.0
        )
        let limitedHistory = history.take(
            between: (startDate + 5.0)...(startDate + 10.0)
        )

        let expectedHistory = AppStateHistory(
            initialState: .init(isActive: true, date: startDate + 5.0),
            changes: [],
            finalDate: startDate + 10.0
        )
        XCTAssertEqual(limitedHistory, expectedHistory)
    }

    func testLimitingWithChanges() {
        let startDate = Date(timeIntervalSinceReferenceDate: 0.0)
        let firstChanges = (0...100).map { _ in
            AppStateHistory.Snapshot(
                isActive: false,
                date: startDate + TimeInterval.random(in: 1...1_000)
            )
        }
        let lastChanges = (0...100).map { _ in
            AppStateHistory.Snapshot(
                isActive: true,
                date: startDate + TimeInterval.random(in: 2_000...3_000)
            )
        }
        var allChanges = (firstChanges + lastChanges)
        allChanges.append(.init(isActive: true, date: startDate + 1_200))
        allChanges.append(.init(isActive: false, date: startDate + 1_500))
        allChanges.sort { $0.date < $1.date }
        let history = AppStateHistory(
            initialState: .init(isActive: true, date: startDate),
            changes: allChanges,
            finalDate: startDate + 4_000
        )

        let limitedHistory = history.take(
            between: (startDate + 1_250)...(startDate + 1_750)
        )

        let expectedHistory = AppStateHistory(
            initialState: .init(isActive: true, date: startDate + 1_250),
            changes: [.init(isActive: false, date: startDate + 1_500)],
            finalDate: startDate + 1_750
        )
        XCTAssertEqual(limitedHistory, expectedHistory)
    }
}

class AppStateListenerTests: XCTestCase {
    private let notificationCenter = NotificationCenter()

    func testWhenAppResignActiveAndBecomeActive_thenAppStateHistoryIsRecorded() {
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let listener = AppStateListener(
            dateProvider: RelativeDateProvider(startingFrom: startDate, advancingBySeconds: 1.0),
            notificationCenter: notificationCenter
        )

        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)

        let expected = AppStateHistory(
            initialState: .init(isActive: true, date: startDate),
            changes: [
                .init(isActive: false, date: startDate + 1.0),
                .init(isActive: true, date: startDate + 2.0)
            ],
            finalDate: startDate + 3.0
        )
        XCTAssertEqual(listener.history, expected)
    }

    func testWhenAppBecomeActiveAndResignActive_thenAppStateHistoryIsRecorded() {
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let listener = AppStateListener(
            dateProvider: RelativeDateProvider(startingFrom: startDate, advancingBySeconds: 1.0),
            notificationCenter: notificationCenter
        )
        notificationCenter.post(name: UIApplication.didBecomeActiveNotification, object: nil)
        notificationCenter.post(name: UIApplication.willResignActiveNotification, object: nil)

        let expected = AppStateHistory(
            initialState: .init(isActive: true, date: startDate),
            changes: [
                .init(isActive: true, date: startDate + 1.0),
                .init(isActive: false, date: startDate + 2.0)
            ],
            finalDate: startDate + 3.0
        )
        XCTAssertEqual(listener.history, expected)
    }

    func testWhenAppStateHistoryIsRetrieved_thenFinalDateOfHistoryChanges() {
        let startDate = Date.mockDecember15th2019At10AMUTC()
        let listener = AppStateListener(
            dateProvider: RelativeDateProvider(startingFrom: startDate, advancingBySeconds: 1.0),
            notificationCenter: notificationCenter
        )
        let history1 = listener.history
        let history2 = listener.history

        XCTAssertEqual(history2.finalState.date.timeIntervalSince(history1.finalState.date), 1.0)
    }

    func testWhenAppStateListenerIsCalledFromDifferentThreads_thenItWorks() {
        let listener = AppStateListener(
            dateProvider: SystemDateProvider(),
            notificationCenter: notificationCenter
        )
        DispatchQueue.concurrentPerform(iterations: 10_000) { iteration in
            // write
            if iteration < 1_000 {
                notificationCenter.post(
                    name: (Bool.random() ?
                            UIApplication.willResignActiveNotification :
                            UIApplication.didBecomeActiveNotification),
                    object: nil
                )
            }
            // read
            XCTAssertFalse(listener.history.changes.isEmpty)
        }
    }
}
