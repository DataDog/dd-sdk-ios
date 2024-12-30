/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
@testable import DatadogRUM

class ITNVMetricTests: XCTestCase {
    private var metric: ITNVMetric! // swiftlint:disable:this implicitly_unwrapped_optional
    private let previousViewID: RUMUUID = .mockRandom()
    private let currentViewID: RUMUUID = .mockRandom()
    private let currentViewStart = Date()

    override func setUp() {
        metric = ITNVMetric()
    }

    override func tearDown() {
        metric = nil
    }

    func testMetricValueIsCalculatedDifferentlyForEachActionType() {
        let actionStart = Date()
        let actionEnd = actionStart + 1.seconds
        let viewStart = actionEnd + 1.05.seconds

        func when(actionType: RUMActionType) -> TimeInterval? {
            // Given
            let metric = ITNVMetric()

            // When
            metric.trackViewStart(at: .distantPast, viewID: previousViewID)
            metric.trackAction(startTime: actionStart, endTime: actionEnd, actionType: actionType, in: previousViewID)
            metric.trackViewStart(at: viewStart, viewID: currentViewID)

            // Then
            return metric.value(for: currentViewID)
        }

        // Then
        let timeSinceActionStart = viewStart.timeIntervalSince(actionStart)
        let timeSinceActionEnd = viewStart.timeIntervalSince(actionEnd)
        XCTAssertEqual(when(actionType: .tap)!, timeSinceActionStart, accuracy: 0.01, "For TAP, the ITNV value should be calculated from the start of the action.")
        XCTAssertEqual(when(actionType: .click)!, timeSinceActionStart, accuracy: 0.01, "For CLICK, the ITNV value should be calculated from the start of the action.")
        XCTAssertEqual(when(actionType: .swipe)!, timeSinceActionEnd, accuracy: 0.01, "For SWIPE, the ITNV value should be calculated from the end of the action.")
        XCTAssertNil(when(actionType: .scroll), "The value should not be calculated for SCROLL actions.")
        XCTAssertNil(when(actionType: .custom), "The value should not be calculated for CUSTOM actions.")
    }

    func testWhenViewStarts_thenMetricValueIsAvailable() throws {
        let (t0, t1, t2) = (currentViewStart - 2.5, currentViewStart - 1, currentViewStart)

        // Given
        metric.trackViewStart(at: .distantPast, viewID: previousViewID)
        metric.trackAction(startTime: t0, endTime: t1, actionType: .tap, in: previousViewID)

        // When
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should be nil before the current view starts.")
        metric.trackViewStart(at: t2, viewID: currentViewID)

        // Then
        let itnv = try XCTUnwrap(metric.value(for: currentViewID), "The ITNV value should be available after the current view starts.")
        XCTAssertEqual(itnv, 2.5, accuracy: 0.01, "The ITNV value should match the time interval from action start to view start.")
    }

    func testWhenViewCompletes_thenMetricValueIsNoLongerAvailable() {
        let (t0, t1, t2) = (currentViewStart - 2.5, currentViewStart - 1, currentViewStart)

        // Given
        metric.trackViewStart(at: .distantPast, viewID: previousViewID)
        metric.trackAction(startTime: t0, endTime: t1, actionType: .tap, in: previousViewID)
        metric.trackViewStart(at: t2, viewID: currentViewID)
        XCTAssertNotNil(metric.value(for: currentViewID), "The ITNV value should be available before the view completes.")

        // When
        metric.trackViewComplete(viewID: currentViewID)

        // Then
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should be removed once the view completes.")
    }

    func testWhenAnotherViewStarts_thenMetricValueIsAvailableUntilViewCompletes() throws {
        let (t0, t1, t2, t3) = (currentViewStart - 2.5, currentViewStart - 1, currentViewStart, currentViewStart + 1.2)

        // Given
        metric.trackViewStart(at: .distantPast, viewID: previousViewID)
        metric.trackAction(startTime: t0, endTime: t1, actionType: .tap, in: previousViewID)
        metric.trackViewStart(at: t2, viewID: currentViewID)

        // When
        let itnv1 = try XCTUnwrap(metric.value(for: currentViewID), "The ITNV value should be available before the current view completes.")
        metric.trackViewStart(at: t3, viewID: .mockRandom()) // another view starts
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
        metric.trackViewStart(at: .distantPast, viewID: previousViewID)

        // When
        metric.trackViewStart(at: t1, viewID: currentViewID)
        let itnv1 = metric.value(for: currentViewID)

        metric.trackAction(startTime: t0, endTime: t0 + 0.1, actionType: .tap, in: previousViewID)
        let itnv2 = try XCTUnwrap(metric.value(for: currentViewID))

        // Then
        XCTAssertNil(itnv1)
        XCTAssertEqual(itnv2, 1.5, accuracy: 0.01)
    }

    func testWhenPreviousViewCompletes_thenMetricValueIsStillAvailable() throws {
        let (t0, t1) = (currentViewStart - 1.5, currentViewStart)

        // Given
        metric.trackViewStart(at: .distantPast, viewID: previousViewID)
        metric.trackAction(startTime: t0, endTime: t0 + 0.1, actionType: .tap, in: previousViewID)
        metric.trackViewStart(at: t1, viewID: currentViewID)

        // When
        metric.trackViewComplete(viewID: previousViewID)

        // Then
        XCTAssertNotNil(metric.value(for: currentViewID))
    }

    func testWhenITNVExceedsMaxDuration_thenMetricValueIsNil() {
        let maxDuration = ITNVMetric.Constants.maxDuration + 0.01
        let (t0, t1, t2) = (currentViewStart - maxDuration, currentViewStart - 1, currentViewStart)

        // Given
        metric.trackViewStart(at: .distantPast, viewID: previousViewID)
        metric.trackAction(startTime: t0, endTime: t1, actionType: .tap, in: previousViewID)

        // When
        metric.trackViewStart(at: t2, viewID: currentViewID)

        // Then
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should not be stored when the duration exceeds the maximum allowed.")
    }

    func testWhenNoActionIsTracked_thenMetricHasNoValue() {
        let (t0, t1) = (currentViewStart - 1, currentViewStart)

        // Given
        metric.trackViewStart(at: t0, viewID: previousViewID)

        // When
        metric.trackViewStart(at: t1, viewID: currentViewID)

        // Then
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should be nil when no actions are tracked.")
    }

    func testWhenNoPreviousViewIsTracked_thenMetricHasNoValue() {
        // When
        metric.trackViewStart(at: currentViewStart, viewID: currentViewID)

        // Then
        XCTAssertNil(metric.value(for: currentViewID), "The ITNV value should be nil when no previous view is tracked.")
    }
}
