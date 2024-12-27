/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
@testable import DatadogRUM

private struct NextViewActionPredicateMock: NextViewActionPredicate {
    let shouldConsiderLastAction: (ITNVActionParams) -> Bool

    func isLastAction(action: ITNVActionParams) -> Bool {
        shouldConsiderLastAction(action)
    }
}

class ITNVMetricTests: XCTestCase {
    private let previousViewID: RUMUUID = .mockRandom()
    private let currentViewID: RUMUUID = .mockRandom()
    private let currentViewStart = Date()

    /// Mock predicate that accepts all actions as the "last" one.
    private let mockAcceptAllActionsPredicate = NextViewActionPredicateMock(shouldConsiderLastAction: { _ in true })
    /// Mock predicate that rejects all actions as the "last" one.
    private let mockRejectAllActionsPredicate = NextViewActionPredicateMock(shouldConsiderLastAction: { _ in false })

    /// Creates `ITNVMetric` instance for testing.
    private func createMetric(nextViewActionPredicate: NextViewActionPredicate) -> ITNVMetric {
        return ITNVMetric(predicate: nextViewActionPredicate)
    }

    // MARK: - "Last Action" Classification

    func testGivenTimeBasedActionPredicate_whenViewStartsSoonerThanThreshold_thenMetricValueIsAvailable() throws {
        let threshold = TimeBasedITNVActionPredicate.defaultMaxTimeToNextView

        func when(timeToNextView: TimeInterval) -> TimeInterval? {
            // Given
            let predicate = TimeBasedITNVActionPredicate(maxTimeToNextView: threshold)
            let metric = createMetric(nextViewActionPredicate: predicate)

            // When
            let actionStartTime = currentViewStart - timeToNextView
            metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)
            metric.trackAction(startTime: actionStartTime, endTime: actionStartTime, name: .mockAny(), type: .tap, in: previousViewID)
            metric.trackViewComplete(viewID: previousViewID)
            metric.trackViewStart(at: currentViewStart, name: .mockAny(), viewID: currentViewID)

            // Then
            return metric.value(for: currentViewID)
        }

        XCTAssertNotNil(when(timeToNextView: threshold))
        XCTAssertNotNil(when(timeToNextView: threshold * 0.5))
        XCTAssertNotNil(when(timeToNextView: threshold * 0.99))

        XCTAssertNil(when(timeToNextView: threshold * 1.01))
        XCTAssertNil(when(timeToNextView: -threshold))
        XCTAssertNil(when(timeToNextView: threshold * 10))
    }

    // MARK: - "Last Action" Classification With Custom Predicate

    func testWhenActionIsAcceptedByPredicate_thenMetricValueIsAvailable() {
        let (t0, t1, t2) = (currentViewStart - 10, currentViewStart - 5, currentViewStart)
        let predicate = mockAcceptAllActionsPredicate

        // Given
        let metric = createMetric(nextViewActionPredicate: predicate)
        metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)

        // When
        metric.trackAction(startTime: t0, endTime: t1, name: .mockAny(), type: .tap, in: previousViewID)
        metric.trackViewStart(at: t2, name: .mockAny(), viewID: currentViewID)

        // Then
        XCTAssertNotNil(metric.value(for: currentViewID), "The ITNV value should be available if any action was accepted.")
    }

    func testWhenActionIsRejectedByPredicate_thenMetricValueIsNotAvailable() {
        let (t0, t1, t2) = (currentViewStart - 10, currentViewStart - 5, currentViewStart)
        let predicate = mockRejectAllActionsPredicate

        // Given
        let metric = createMetric(nextViewActionPredicate: predicate)
        metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)

        // When
        metric.trackAction(startTime: t0, endTime: t1, name: .mockAny(), type: .tap, in: previousViewID)
        metric.trackViewStart(at: t2, name: .mockAny(), viewID: currentViewID)

        // Then
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should not be available if no action was accepted.")
    }

    func testMetricValueIsComputedFromAcceptedAction() throws {
        let actions: [(date: Date, name: String)] = [
            (currentViewStart - 5, "Action 1"),
            (currentViewStart - 4, "Action 2"),
            (currentViewStart - 3, "Action 3"),
            (currentViewStart - 2, "Action 4"),
            (currentViewStart - 1, "Action 5"),
        ]
        let predicate = NextViewActionPredicateMock(shouldConsiderLastAction: { $0.name == "Action 3" })

        // Given
        let metric = createMetric(nextViewActionPredicate: predicate)
        metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)
        actions.forEach {
            metric.trackAction(startTime: $0.date, endTime: $0.date, name: $0.name, type: .tap, in: previousViewID)
        }

        // When
        metric.trackViewStart(at: currentViewStart, name: .mockAny(), viewID: currentViewID)

        // Then
        let itnv = try XCTUnwrap(metric.value(for: currentViewID))
        XCTAssertEqual(itnv, 3, accuracy: 0.01, "The ITNV value should be computed from accepted action (Action 3).")
    }

    // MARK: - Metric Value

    func testMetricValueIsCalculatedDifferentlyForEachActionType() {
        let actionStart = Date()
        let actionEnd = actionStart + 1.seconds
        let viewStart = actionEnd + 1.05.seconds

        func when(actionType: RUMActionType) -> TimeInterval? {
            // Given
            let metric = createMetric(nextViewActionPredicate: mockAcceptAllActionsPredicate)

            // When
            metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)
            metric.trackAction(startTime: actionStart, endTime: actionEnd, name: .mockAny(), type: actionType, in: previousViewID)
            metric.trackViewStart(at: viewStart, name: .mockAny(), viewID: currentViewID)

            // Then
            return metric.value(for: currentViewID)
        }

        // Then
        let timeSinceActionStart = viewStart.timeIntervalSince(actionStart)
        let timeSinceActionEnd = viewStart.timeIntervalSince(actionEnd)
        XCTAssertEqual(when(actionType: .tap)!, timeSinceActionStart, accuracy: 0.01, "For TAP, the ITNV value should be calculated from the start of the action.")
        XCTAssertEqual(when(actionType: .click)!, timeSinceActionStart, accuracy: 0.01, "For CLICK, the ITNV value should be calculated from the start of the action.")
        XCTAssertEqual(when(actionType: .swipe)!, timeSinceActionEnd, accuracy: 0.01, "For SWIPE, the ITNV value should be calculated from the end of the action.")
        XCTAssertEqual(when(actionType: .scroll)!, timeSinceActionEnd, accuracy: 0.01, "For SCROLL, the ITNV value should be calculated from the end of the action.")
        XCTAssertEqual(when(actionType: .custom)!, timeSinceActionStart, accuracy: 0.01, "For CUSTOM actions, the ITNV value should be calculated from the start of the action.")
    }

    // MARK: - Value Availability vs View Completion

    func testWhenViewStartsBeforePreviousViewCompletes_thenMetricValueIsAvailable() throws {
        let (t0, t1, t2) = (currentViewStart - 2.5, currentViewStart - 1, currentViewStart)

        // Given
        let metric = createMetric(nextViewActionPredicate: mockAcceptAllActionsPredicate)
        metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)
        metric.trackAction(startTime: t0, endTime: t1, name: .mockAny(), type: .tap, in: previousViewID)

        // When
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should be nil before the current view starts.")
        metric.trackViewStart(at: t2, name: .mockAny(), viewID: currentViewID)

        // Then
        let itnv = try XCTUnwrap(metric.value(for: currentViewID), "The ITNV value should be available after the current view starts.")
        XCTAssertEqual(itnv, 2.5, accuracy: 0.01, "The ITNV value should match the time interval from action start to view start.")
    }

    func testWhenViewStartsAfterPreviousViewCompletes_thenMetricValueIsAvailable() throws {
        let (t0, t1, t2) = (currentViewStart - 2.5, currentViewStart - 1, currentViewStart)

        // Given
        let metric = createMetric(nextViewActionPredicate: mockAcceptAllActionsPredicate)
        metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)
        metric.trackAction(startTime: t0, endTime: t1, name: .mockAny(), type: .tap, in: previousViewID)

        // When
        metric.trackViewComplete(viewID: previousViewID)
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should be nil before the current view starts.")
        metric.trackViewStart(at: t2, name: .mockAny(), viewID: currentViewID)

        // Then
        let itnv = try XCTUnwrap(metric.value(for: currentViewID), "The ITNV value should be available after the current view starts.")
        XCTAssertEqual(itnv, 2.5, accuracy: 0.01, "The ITNV value should match the time interval from action start to view start.")
    }

    func testWhenViewCompletes_thenMetricValueIsNoLongerAvailable() {
        let (t0, t1, t2) = (currentViewStart - 2.5, currentViewStart - 1, currentViewStart)

        // Given
        let metric = createMetric(nextViewActionPredicate: mockAcceptAllActionsPredicate)
        metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)
        metric.trackAction(startTime: t0, endTime: t1, name: .mockAny(), type: .tap, in: previousViewID)
        metric.trackViewStart(at: t2, name: .mockAny(), viewID: currentViewID)
        XCTAssertNotNil(metric.value(for: currentViewID), "The ITNV value should be available before the view completes.")

        // When
        metric.trackViewComplete(viewID: currentViewID)

        // Then
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should be removed once the view completes.")
    }

    func testWhenAnotherViewStarts_thenMetricValueIsAvailableUntilViewCompletes() throws {
        let (t0, t1, t2, t3) = (currentViewStart - 2.5, currentViewStart - 1, currentViewStart, currentViewStart + 1.2)

        // Given
        let metric = createMetric(nextViewActionPredicate: mockAcceptAllActionsPredicate)
        metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)
        metric.trackAction(startTime: t0, endTime: t1, name: .mockAny(), type: .tap, in: previousViewID)
        metric.trackViewStart(at: t2, name: .mockAny(), viewID: currentViewID)

        // When
        let itnv1 = try XCTUnwrap(metric.value(for: currentViewID), "The ITNV value should be available before the current view completes.")
        metric.trackViewStart(at: t3, name: .mockAny(), viewID: .mockRandom()) // another view starts
        let itnv2 = try XCTUnwrap(metric.value(for: currentViewID), "The ITNV value should remain available before the current view completes.")
        metric.trackViewComplete(viewID: currentViewID) // view completes

        // Then
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should be removed after the view completes.")
        XCTAssertEqual(itnv1, 2.5, accuracy: 0.01, "The first ITNV value should match the time interval from action start to view start.")
        XCTAssertEqual(itnv2, itnv2, accuracy: 0.01, "The second ITNV value should be the same as the first one, unaffected by the new view.")
    }

    func testWhenActionIsTrackedInPreviousViewAfterCurrentViewIsStarted_thenMetricValueIsUpdated() throws {
        let (t0, t1) = (currentViewStart - 1.5, currentViewStart)

        // Given
        let metric = createMetric(nextViewActionPredicate: mockAcceptAllActionsPredicate)
        metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)

        // When
        metric.trackViewStart(at: t1, name: .mockAny(), viewID: currentViewID)
        let itnv1 = metric.value(for: currentViewID)

        metric.trackAction(startTime: t0, endTime: t0 + 0.1, name: .mockAny(), type: .tap, in: previousViewID)
        let itnv2 = try XCTUnwrap(metric.value(for: currentViewID))

        // Then
        XCTAssertNil(itnv1)
        XCTAssertEqual(itnv2, 1.5, accuracy: 0.01)
    }

    func testWhenPreviousViewCompletes_thenMetricValueIsStillAvailable() throws {
        let (t0, t1) = (currentViewStart - 1.5, currentViewStart)

        // Given
        let metric = createMetric(nextViewActionPredicate: mockAcceptAllActionsPredicate)
        metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)
        metric.trackAction(startTime: t0, endTime: t0 + 0.1, name: .mockAny(), type: .tap, in: previousViewID)
        metric.trackViewStart(at: t1, name: .mockAny(), viewID: currentViewID)

        // When
        metric.trackViewComplete(viewID: previousViewID)

        // Then
        XCTAssertNotNil(metric.value(for: currentViewID))
    }

    // MARK: - Interaction With Predicate

    func testWhenComputingMetricValue_itCallsPredicateWithAllActionsOnlyOnce() throws {
        let actions: [(date: Date, name: String)] = [
            (currentViewStart - 5, "Action 1"),
            (currentViewStart - 4, "Action 2"),
            (currentViewStart - 3, "Action 3"),
            (currentViewStart - 2, "Action 4"),
            (currentViewStart - 1, "Action 5"),
        ]
        var actionNamesInPredicate: [String] = []
        let predicate = NextViewActionPredicateMock(shouldConsiderLastAction: {
            actionNamesInPredicate.append($0.name) // track each
            return false // accept none
        })

        // Given
        let metric = createMetric(nextViewActionPredicate: predicate)
        metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)
        actions.forEach {
            metric.trackAction(startTime: $0.date, endTime: $0.date, name: $0.name, type: .tap, in: previousViewID)
        }
        metric.trackViewStart(at: currentViewStart, name: .mockAny(), viewID: currentViewID)

        // When (compute metric multiple times)
        _ = metric.value(for: currentViewID)
        _ = metric.value(for: currentViewID)
        _ = metric.value(for: currentViewID)

        // Then
        let expectedActions = Array(actions.map({ $0.name }).reversed())
        XCTAssertEqual(actionNamesInPredicate, expectedActions, "It should call predicate with all actions, starting from the youngest one")
    }

    func testWhenComputingMetricValue_itCallsPredicateWithAllActionsFromPreviousView() throws {
        struct ActionFixture {
            let name: String
            let type: RUMActionType = .tap
            let startTime: Date
            var endTime: Date { startTime + 0.1 }
        }

        struct ViewFixture {
            let id: RUMUUID = .mockRandom()
            let name: String
            let startTime: Date
            let actions: [ActionFixture]
        }

        let view1Start = Date()
        let view2Start = view1Start + 10
        let view3Start = view2Start + 10

        let viewFixtures: [ViewFixture] = [
            ViewFixture(
                name: "View 1",
                startTime: view1Start,
                actions: [
                    ActionFixture(name: "Action 1A", startTime: view1Start + 1),
                    ActionFixture(name: "Action 1B", startTime: view1Start + 2),
                    ActionFixture(name: "Action 1C", startTime: view1Start + 3),
                ]
            ),
            ViewFixture(
                name: "View 2",
                startTime: view2Start,
                actions: [
                    ActionFixture(name: "Action 2A", startTime: view2Start + 1),
                    ActionFixture(name: "Action 2B", startTime: view2Start + 2),
                ]
            ),
            ViewFixture(
                name: "View 3",
                startTime: view3Start,
                actions: [
                    ActionFixture(name: "Action 3A", startTime: view3Start + 1),
                ]
            )
        ]

        var actionsInPredicate: [ITNVActionParams] = []
        let predicate = NextViewActionPredicateMock(shouldConsiderLastAction: {
            actionsInPredicate.append($0) // track all
            return false // accept none
        })

        // Given
        let metric = createMetric(nextViewActionPredicate: predicate)

        for view in viewFixtures {
            metric.trackViewStart(at: view.startTime, name: view.name, viewID: view.id)

            // When
            _ = metric.value(for: view.id)

            for action in view.actions {
                metric.trackAction(startTime: action.startTime, endTime: action.endTime, name: action.name, type: action.type, in: view.id)
            }
            metric.trackViewComplete(viewID: view.id)
        }

        // Then
        XCTAssertEqual(actionsInPredicate.count, 5)
        DDAssertReflectionEqual(actionsInPredicate[0], ITNVActionParams(type: .tap, name: "Action 1C", timeToNextView: 7, nextViewName: "View 2"))
        DDAssertReflectionEqual(actionsInPredicate[1], ITNVActionParams(type: .tap, name: "Action 1B", timeToNextView: 8, nextViewName: "View 2"))
        DDAssertReflectionEqual(actionsInPredicate[2], ITNVActionParams(type: .tap, name: "Action 1A", timeToNextView: 9, nextViewName: "View 2"))
        DDAssertReflectionEqual(actionsInPredicate[3], ITNVActionParams(type: .tap, name: "Action 2B", timeToNextView: 8, nextViewName: "View 3"))
        DDAssertReflectionEqual(actionsInPredicate[4], ITNVActionParams(type: .tap, name: "Action 2A", timeToNextView: 9, nextViewName: "View 3"))
    }

    // MARK: - Edge Cases

    func testWhenNoActionIsTracked_thenMetricHasNoValue() {
        let (t0, t1) = (currentViewStart - 1, currentViewStart)

        // Given
        let metric = createMetric(nextViewActionPredicate: mockAcceptAllActionsPredicate)
        metric.trackViewStart(at: t0, name: .mockAny(), viewID: previousViewID)

        // When
        metric.trackViewStart(at: t1, name: .mockAny(), viewID: currentViewID)

        // Then
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should be nil when no actions are tracked.")
    }

    func testWhenNoPreviousViewIsTracked_thenMetricHasNoValue() {
        // When
        let metric = createMetric(nextViewActionPredicate: mockAcceptAllActionsPredicate)
        metric.trackViewStart(at: currentViewStart, name: .mockAny(), viewID: currentViewID)

        // Then
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should be nil when no previous view is tracked.")
    }

    func testWhenActionIsEarlierThanPreviousViewStart_thenItIsIgnored() throws {
        let previousViewStart = currentViewStart - 10
        let invalidActionDate = previousViewStart - 5

        // Given
        let metric = createMetric(nextViewActionPredicate: mockAcceptAllActionsPredicate)
        metric.trackViewStart(at: previousViewStart, name: .mockAny(), viewID: previousViewID)

        // When
        metric.trackAction(startTime: invalidActionDate, endTime: invalidActionDate, name: .mockAny(), type: .tap, in: previousViewID)

        // Then
        metric.trackViewStart(at: currentViewStart, name: .mockAny(), viewID: currentViewID)
        XCTAssertNil(metric.value(for: currentViewID))
    }

    func testTrackingActionsInNotStartedViewsHasNoEffect() throws {
        let actionDate = currentViewStart - 1

        // Given
        let metric = createMetric(nextViewActionPredicate: mockAcceptAllActionsPredicate)
        metric.trackViewStart(at: .distantPast, name: .mockAny(), viewID: previousViewID)
        metric.trackAction(startTime: actionDate, endTime: actionDate, name: .mockAny(), type: .tap, in: previousViewID)
        metric.trackViewStart(at: currentViewStart, name: .mockAny(), viewID: currentViewID)

        // When
        let notStartedViewID: RUMUUID = .mockRandom()
        metric.trackAction(startTime: .mockRandom(), endTime: .mockRandom(), name: .mockAny(), type: .tap, in: notStartedViewID)

        // Then
        let actualITNV = try XCTUnwrap(metric.value(for: currentViewID))
        let expectedITNV = currentViewStart.timeIntervalSince(actionDate)
        XCTAssertEqual(actualITNV, expectedITNV, accuracy: 0.01)
    }
}
