/*
 * Unless explicitly stated otherwise all files in this repository are licensed under the Apache License Version 2.0.
 * This product includes software developed at Datadog (https://www.datadoghq.com/).
 * Copyright 2019-Present Datadog, Inc.
 */

import XCTest
import TestUtilities
import DatadogInternal
@testable import DatadogRUM

private extension RUMUUID {
    static let resource1 = RUMUUID(rawValue: UUID())
    static let resource2 = RUMUUID(rawValue: UUID())
    static let resource3 = RUMUUID(rawValue: UUID())
    static let resource4 = RUMUUID(rawValue: UUID())
}

class TTNSMetricTests: XCTestCase {
    private var metric: TTNSMetric! // swiftlint:disable:this implicitly_unwrapped_optional
    private let t100ms = TTNSMetric.Constants.initialResourceThreshold
    private let viewStartDate = Date()

    override func setUp() {
        metric = TTNSMetric(viewStartDate: viewStartDate)
    }

    override func tearDown() {
        metric = nil
    }

    // MARK: - "Initial Resource" Classification

    func testWhenResourceStartsWithinThreshold_thenResourceIsTracked() throws {
        func when(resourceStartOffset offset: TimeInterval) -> TimeInterval? {
            // Given
            let metric = TTNSMetric(viewStartDate: viewStartDate)

            // When
            var now = viewStartDate + offset
            metric.trackResourceStart(at: now, resourceID: .resource1)
            now.addTimeInterval(1.42)
            metric.trackResourceEnd(at: now, resourceID: .resource1, resourceDuration: nil)

            // Then
            return metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: viewStartDate))
        }

        // When resource starts within threshold (initial resource), it should be tracked:
        XCTAssertNotNil(when(resourceStartOffset: 0), "Resource starting at `view start` should be tracked as an initial resource.")
        XCTAssertNotNil(when(resourceStartOffset: t100ms * 0.5), "Resource starting at `view start + \(t100ms * 0.5)s` should be tracked as an initial resource.")
        XCTAssertNotNil(when(resourceStartOffset: t100ms * 0.999), "Resource starting at `view start + \(t100ms * 0.999)s` should be tracked as an initial resource.")

        // When resource starts outside threshold (other resource), it should not be tracked:
        XCTAssertNil(when(resourceStartOffset: t100ms), "Resource starting at `view start + \(t100ms)s` should not be tracked as an initial resource.")
        XCTAssertNil(when(resourceStartOffset: -t100ms), "Resource starting at `view start + \(-t100ms)s` should not be tracked as an initial resource.")
        XCTAssertNil(when(resourceStartOffset: t100ms * 10), "Resource starting at `view start + \(t100ms * 10)s` should not be tracked as an initial resource.")
    }

    // MARK: - Metric Value vs Resource Completion

    func testWhenResourceCompletesWithNoDuration_thenMetricValueIsCalculatedFromResourceEndDate() throws {
        // Given
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1)

        // When
        let resourceEndDate = viewStartDate.addingTimeInterval(1.1)
        metric.trackResourceEnd(at: resourceEndDate, resourceID: .resource1, resourceDuration: nil)

        // Then
        let ttns = try XCTUnwrap(metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: viewStartDate)))
        XCTAssertEqual(ttns, resourceEndDate.timeIntervalSince(viewStartDate), accuracy: 0.01, "Metric value should be calculated from resource end time.")
    }

    func testWhenResourceCompletesWithDuration_thenMetricValueIsCalculatedFromResourceDuration() throws {
        // Given
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1)

        // When
        let resourceEndDate = viewStartDate.addingTimeInterval(.mockRandom(min: 0, max: 100))
        let resourceDuration: TimeInterval = 1.2
        metric.trackResourceEnd(at: resourceEndDate, resourceID: .resource1, resourceDuration: resourceDuration)

        // Then
        let ttns = try XCTUnwrap(metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: viewStartDate)))
        XCTAssertEqual(ttns, resourceDuration, accuracy: 0.01, "Metric value should be calculated from resource duration.")
    }

    func testMetricValueIsOnlyAvailableAfterAllInitialResourcesComplete() {
        // Given
        let t0 = viewStartDate // initial resource
        let t1 = viewStartDate + t100ms // other resource
        metric.trackResourceStart(at: t0, resourceID: .resource1)
        metric.trackResourceStart(at: t0, resourceID: .resource2)
        metric.trackResourceStart(at: t0, resourceID: .resource3)
        metric.trackResourceStart(at: t1, resourceID: .resource4)
        XCTAssertNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: t0)),
            "Metric value should be nil while initial resources are pending."
        )

        // When (complete initial resource) / Then (metric has no value)
        metric.trackResourceEnd(at: t0 + 1, resourceID: .resource1, resourceDuration: nil)
        XCTAssertNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: t0)),
            "Metric value should be nil while initial resources are pending."
        )

        // When (complete initial resource) / Then (metric has no value)
        metric.trackResourceEnd(at: t0 + 1, resourceID: .resource2, resourceDuration: nil)
        XCTAssertNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: t0)),
            "Metric value should be nil while initial resources are pending."
        )

        // When (complete initial resource) / Then (metric has value)
        metric.trackResourceEnd(at: t0 + 1, resourceID: .resource3, resourceDuration: nil)
        XCTAssertNotNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: t0)),
            "Metric value should be set after all initial resources are completed."
        )

        // When (complete other resource) / Then (metric not changed)
        metric.trackResourceEnd(at: t1 + 1, resourceID: .resource4, resourceDuration: nil)
        XCTAssertEqual(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: t0)),
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: t0)),
            "Metric value should not change after other resources complete."
        )
    }

    func testWhenMultipleInitialResourcesComplete_thenMetricValueReflectsLastCompletedResource() throws {
        // Given
        let t0 = viewStartDate // initial resource
        let t1 = viewStartDate + t100ms * 0.33 // initial resource
        let t2 = viewStartDate + t100ms * 0.66 // initial resource
        metric.trackResourceStart(at: t0, resourceID: .resource1)
        metric.trackResourceStart(at: t1, resourceID: .resource2)
        metric.trackResourceStart(at: t2, resourceID: .resource3)

        // When
        let durations: [TimeInterval] = [10, 15, 20].shuffled()
        metric.trackResourceEnd(at: t0 + durations[0], resourceID: .resource1, resourceDuration: nil)
        metric.trackResourceEnd(at: t0 + durations[1], resourceID: .resource2, resourceDuration: nil)
        metric.trackResourceEnd(at: t0 + durations[2], resourceID: .resource3, resourceDuration: nil)

        // Then
        let ttns = try XCTUnwrap(metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: t0)))
        XCTAssertEqual(ttns, durations.max()!, accuracy: 0.01, "Metric value should reflect the completion of the last initial resource.")
    }

    // MARK: - Metric Value vs Resource Dropped

    func testWhenAllResourcesAreDropped_thenMetricValueIsNotAvailable() throws {
        // Given
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource2)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource3)

        // When
        metric.trackResourceDropped(resourceID: .resource1)
        metric.trackResourceDropped(resourceID: .resource2)
        metric.trackResourceDropped(resourceID: .resource3)

        // Then
        XCTAssertNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: viewStartDate)),
            "Metric value should not be available if all resources are dropped."
        )
    }

    func testWhenSomeResourcesAreDropped_thenMetricValueReflectsCompletedResources() throws {
        // Given
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource2)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource3)

        // When
        metric.trackResourceEnd(at: viewStartDate + 1.42, resourceID: .resource1, resourceDuration: nil)
        metric.trackResourceDropped(resourceID: .resource2)
        metric.trackResourceDropped(resourceID: .resource3)

        // Then
        let ttns = try XCTUnwrap(metric.value(at: viewStartDate + 10, appStateHistory: .mockAppInForeground(since: viewStartDate)))
        XCTAssertEqual(ttns, 1.42, accuracy: 0.01, "Metric value should reflect completed resources.")
    }

    // MARK: - Metric Value vs Initial Resource Threshold

    func testWhenNewInitialResourceStartsAfterPreviousComplete_thenMetricValueIsOnlyAvailableAfterThreshold() throws {
        // Given
        let t0 = viewStartDate // initial resource
        let t1 = viewStartDate + t100ms * 0.33 // initial resource
        let t2 = viewStartDate + t100ms * 0.66 // initial resource
        let t3 = viewStartDate + t100ms * 0.99 // initial resource
        let duration: TimeInterval = t100ms * 0.25

        // When (complete resource before threshold) / Then
        metric.trackResourceStart(at: t0, resourceID: .resource1)
        metric.trackResourceEnd(at: t0 + duration, resourceID: .resource1, resourceDuration: duration)
        XCTAssertNil(
            metric.value(at: t0 + duration, appStateHistory: .mockAppInForeground(since: t0)),
            "Metric value should be not available earlier than \(t100ms)s after view start."
        )

        // When (complete resource before threshold) / Then
        metric.trackResourceStart(at: t1, resourceID: .resource2)
        metric.trackResourceEnd(at: t1 + duration, resourceID: .resource2, resourceDuration: duration)
        XCTAssertNil(
            metric.value(at: t1 + duration, appStateHistory: .mockAppInForeground(since: t0)),
            "Metric value should be not available earlier than \(t100ms)s after view start."
        )

        // When (complete resource before threshold) / Then
        metric.trackResourceStart(at: t2, resourceID: .resource3)
        metric.trackResourceEnd(at: t2 + duration, resourceID: .resource3, resourceDuration: duration)
        XCTAssertNil(
            metric.value(at: t2 + duration, appStateHistory: .mockAppInForeground(since: t0)),
            "Metric value should be not available earlier than \(t100ms)s after view start."
        )

        // When (complete resource after threshold) / Then
        metric.trackResourceStart(at: t3, resourceID: .resource4)
        metric.trackResourceEnd(at: t3 + duration, resourceID: .resource4, resourceDuration: duration)
        let ttns3 = try XCTUnwrap(metric.value(at: t3 + duration, appStateHistory: .mockAppInForeground(since: t0)))
        XCTAssertEqual(ttns3, 0.124, accuracy: 0.01, "Metric value should be available only after the threshold.")
    }

    // MARK: - "View Stopped" Condition

    func testWhenViewIsStopped_thenMetricValueIsNotAvailable() {
        // When
        metric.trackViewWasStopped()
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1)
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: nil)

        // Then
        XCTAssertNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: viewStartDate)),
            "Metric value should not be available when view is stopped."
        )
    }

    func testWhenViewIsStoppedBeforeResourceCompletes_thenMetricValueIsNotAvailable() {
        // Given
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1)

        // When
        metric.trackViewWasStopped()
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: nil)

        // Then
        XCTAssertNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: viewStartDate)),
            "Metric value should not be available if view is stopped before resource completes."
        )
    }

    func testWhenViewIsStoppedAfterResourceCompletes_thenMetricValueIsAvailable() {
        // Given
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1)
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: nil)

        // When
        metric.trackViewWasStopped()

        // Then
        XCTAssertNotNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: viewStartDate)),
            "Metric value should be available if view is stopped after resource completes."
        )
    }

    // MARK: - "App State" Condition

    func testWhenAppStaysActiveDuringViewLoading_thenMetricValueIsAvailable() {
        // Given
        let resourceStart = viewStartDate
        let resourceEnd = resourceStart + 5
        metric.trackResourceStart(at: resourceStart, resourceID: .resource1)
        metric.trackResourceEnd(at: resourceEnd, resourceID: .resource1, resourceDuration: nil)

        // When
        let appStateHistory = AppStateHistory(
            initialSnapshot: .init(state: .active, date: .distantPast),
            recentDate: .distantFuture,
            snapshots: [.init(state: .active, date: .distantFuture)]
        )

        // Then
        XCTAssertNotNil(
            metric.value(at: resourceEnd + 1, appStateHistory: appStateHistory),
            "Metric value should be available if app remains active during view loading."
        )
    }

    func testWhenAppDoesNotStayActiveDuringViewLoading_thenMetricValueIsNotAvailable() {
        // Given
        let resourceStart = viewStartDate
        let resourceDuration: TimeInterval = 5
        let resourceEnd = resourceStart + resourceDuration
        metric.trackResourceStart(at: resourceStart, resourceID: .resource1)
        metric.trackResourceEnd(at: resourceEnd, resourceID: .resource1, resourceDuration: resourceDuration)

        // When
        let appStateHistory = AppStateHistory(
            initialSnapshot: .init(state: .active, date: .distantPast),
            recentDate: .distantFuture,
            snapshots: [
                .init(state: [.inactive, .background].randomElement()!, date: resourceStart + resourceDuration * 0.25),
                .init(state: .active, date: resourceStart + resourceDuration * 0.5),
            ]
        )

        // Then
        XCTAssertNil(
            metric.value(at: resourceEnd + 1, appStateHistory: appStateHistory),
            "Metric value should not be available if app is not active during view loading."
        )
    }

    // MARK: - Edge Cases

    func testWhenNoResourcesAreTracked() {
        XCTAssertNil(
            metric.value(at: .mockAny(), appStateHistory: .mockRandom()),
            "Metric value should be nil if no resources are tracked."
        )
    }

    func testWhenResourceEndsBeforeViewStarts() {
        metric.trackResourceStart(at: viewStartDate - 2, resourceID: .resource1)
        metric.trackResourceEnd(at: viewStartDate - 1, resourceID: .resource1, resourceDuration: nil)
        XCTAssertNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: .distantPast)),
            "Metric value should be nil if resource ends before view starts."
        )
    }

    func testWhenResourceEndsThenStarts() {
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: nil)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1)
        XCTAssertNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: .distantPast)),
            "Metric value should be nil if resource ends before it starts."
        )
    }

    func testWhenResourceEndsEarlierThanItStarts() {
        metric.trackResourceStart(at: viewStartDate + 1, resourceID: .resource1)
        metric.trackResourceEnd(at: viewStartDate + 0.5, resourceID: .resource1, resourceDuration: nil)
        XCTAssertNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: .distantPast)),
            "Metric value should be nil if resource ends earlier than it starts."
        )
    }

    func testWhenResourceEndsImmediately() throws {
        let t0 = viewStartDate + t100ms * 0.5 // initial resource
        metric.trackResourceStart(at: t0, resourceID: .resource1)
        metric.trackResourceEnd(at: t0, resourceID: .resource1, resourceDuration: nil)

        let ttns = try XCTUnwrap(metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: .distantPast)))
        XCTAssertEqual(ttns, t100ms * 0.5, accuracy: 0.01, "Metric value should be equal to resource start offset.")
    }

    func testWhenResourceEndsWithNegativeDuration() throws {
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1)
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: -10)

        XCTAssertNil(
            metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: .distantPast)),
            "Metric should ignore resources with negtative durations."
        )
    }

    func testWhenResourceEndsImmediatelyWithDuration() throws {
        let t0 = viewStartDate + t100ms * 0.5 // initial resource
        let duration: TimeInterval = 10
        metric.trackResourceStart(at: t0, resourceID: .resource1)
        metric.trackResourceEnd(at: t0, resourceID: .resource1, resourceDuration: duration)

        let ttns = try XCTUnwrap(metric.value(at: .distantFuture, appStateHistory: .mockAppInForeground(since: .distantPast)))
        XCTAssertEqual(ttns, duration + t100ms * 0.5, accuracy: 0.01, "Metric value should be equal to resource duration plus resource start offset.")
    }
}
