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
    static let resource5 = RUMUUID(rawValue: UUID())
}

private struct ResourcePredicateMock: NetworkSettledResourcePredicate {
    let shouldConsiderInitialResource: (TNSResourceParams) -> Bool

    func isInitialResource(from resourceParams: TNSResourceParams) -> Bool {
        shouldConsiderInitialResource(resourceParams)
    }
}

class TNSMetricTests: XCTestCase {
    /// Represents 100ms.
    private let t100ms: TimeInterval = 0.1
    /// The start of the view tracked by tested metric.
    private let viewStartDate = Date()
    /// Mock predicate that accepts all resources as "initial".
    private let mockAllInitialResourcesPredicate = ResourcePredicateMock(shouldConsiderInitialResource: { _ in true })
    /// Mock predicate that accepts resources with given URL as "initial".
    private func mockResourcesPredicate(initialResourcesURL: String) -> ResourcePredicateMock {
        ResourcePredicateMock(shouldConsiderInitialResource: { $0.url == initialResourcesURL })
    }
    // swiftlint:disable function_default_parameter_at_end
    /// Creates `TNSMetric` instance for testing.
    private func createMetric(viewName: String = .mockAny(), viewStartDate: Date, resourcePredicate: NetworkSettledResourcePredicate) -> TNSMetric {
        return TNSMetric(viewName: viewName, viewStartDate: viewStartDate, resourcePredicate: resourcePredicate)
    }
    // swiftlint:enable function_default_parameter_at_end

    // MARK: - "Initial Resource" Classification

    func testGivenTimeBasedResourcePredicate_whenResourceStartsWithinThreshold_thenItIsTracked() throws {
        let threshold = TimeBasedTNSResourcePredicate.defaultThreshold

        func when(resourceStartOffset offset: TimeInterval) -> Result<TimeInterval, TNSNoValueReason> {
            // Given
            let predicate = TimeBasedTNSResourcePredicate(threshold: threshold)
            let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: predicate)

            // When
            var now = viewStartDate + offset
            metric.trackResourceStart(at: now, resourceID: .resource1, resourceURL: .mockAny())
            now.addTimeInterval(1.42)
            metric.trackResourceEnd(at: now, resourceID: .resource1, resourceDuration: nil)

            // Then
            return metric.value(with: .mockAppInForeground(since: viewStartDate))
        }

        // When resource starts within threshold (initial resource), it should be tracked:
        XCTAssertTrue(when(resourceStartOffset: 0).isSuccess, "Resource starting at `view start` should be tracked as an initial resource.")
        XCTAssertTrue(when(resourceStartOffset: threshold * 0.5).isSuccess, "Resource starting at `view start + \(threshold * 0.5)s` should be tracked as an initial resource.")
        XCTAssertTrue(when(resourceStartOffset: threshold * 0.999).isSuccess, "Resource starting at `view start + \(threshold * 0.999)s` should be tracked as an initial resource.")

        // When resource starts outside threshold (other resource), it should not be tracked:
        XCTAssertEqual(when(resourceStartOffset: threshold), .failure(.noInitialResources))
        XCTAssertEqual(when(resourceStartOffset: -threshold), .failure(.noInitialResources))
        XCTAssertEqual(when(resourceStartOffset: threshold * 10), .failure(.noInitialResources))
    }

    // MARK: - Metric Value vs Resource Completion

    func testWhenResourceCompletesWithNoDuration_thenMetricValueIsCalculatedFromResourceEndDate() throws {
        // Given
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())

        // When
        let resourceEndDate = viewStartDate.addingTimeInterval(1.1)
        metric.trackResourceEnd(at: resourceEndDate, resourceID: .resource1, resourceDuration: nil)

        // Then
        let ttns = try metric.value(with: .mockAppInForeground(since: viewStartDate)).get()
        XCTAssertEqual(ttns, resourceEndDate.timeIntervalSince(viewStartDate), accuracy: 0.01, "Metric value should be calculated from resource end time.")
    }

    func testWhenResourceCompletesWithDuration_thenMetricValueIsCalculatedFromResourceDuration() throws {
        // Given
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())

        // When
        let resourceEndDate = viewStartDate.addingTimeInterval(.mockRandom(min: 0, max: 100))
        let resourceDuration: TimeInterval = 1.2
        metric.trackResourceEnd(at: resourceEndDate, resourceID: .resource1, resourceDuration: resourceDuration)

        // Then
        let ttns = try metric.value(with: .mockAppInForeground(since: viewStartDate)).get()
        XCTAssertEqual(ttns, resourceDuration, accuracy: 0.01, "Metric value should be calculated from resource duration.")
    }

    func testMetricValueIsOnlyAvailableAfterAllInitialResourcesComplete() {
        // Given
        let initialResourceURL: String = .mockRandom()
        let metric = createMetric(
            viewStartDate: viewStartDate,
            resourcePredicate: mockResourcesPredicate(initialResourcesURL: initialResourceURL)
        )
        let t0 = viewStartDate // initial resource
        let t1 = viewStartDate + t100ms // other resource
        metric.trackResourceStart(at: t0, resourceID: .resource1, resourceURL: initialResourceURL)
        metric.trackResourceStart(at: t0, resourceID: .resource2, resourceURL: initialResourceURL)
        metric.trackResourceStart(at: t0, resourceID: .resource3, resourceURL: initialResourceURL)
        metric.trackResourceStart(at: t1, resourceID: .resource4, resourceURL: .mockRandom())
        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: t0)), .failure(.initialResourcesIncomplete))

        // When (complete first initial resource) / Then (metric has no value)
        metric.trackResourceEnd(at: t0 + 1, resourceID: .resource1, resourceDuration: nil)
        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: t0)), .failure(.initialResourcesIncomplete))

        // When (complete next initial resource) / Then (metric has no value)
        metric.trackResourceEnd(at: t0 + 1, resourceID: .resource2, resourceDuration: nil)
        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: t0)), .failure(.initialResourcesIncomplete))

        // When (complete last initial resource) / Then (metric has value)
        metric.trackResourceEnd(at: t0 + 1, resourceID: .resource3, resourceDuration: nil)
        XCTAssertTrue(
            metric.value(with: .mockAppInForeground(since: t0)).isSuccess,
            "Metric value should be available after all initial resources are completed."
        )

        // When (complete other resource) / Then (metric not changed)
        metric.trackResourceEnd(at: t1 + 1, resourceID: .resource4, resourceDuration: nil)
        XCTAssertEqual(
            metric.value(with: .mockAppInForeground(since: t0)),
            metric.value(with: .mockAppInForeground(since: t0)),
            "Metric value should not change after other resources complete."
        )

        // When (start and complete another resource) / Then (metric not changed)
        metric.trackResourceStart(at: t1 + 2, resourceID: .resource5, resourceURL: .mockRandom())
        metric.trackResourceEnd(at: t1 + 2.5, resourceID: .resource5, resourceDuration: nil)
        XCTAssertEqual(
            metric.value(with: .mockAppInForeground(since: t0)),
            metric.value(with: .mockAppInForeground(since: t0)),
            "Metric value should not change after other resources complete."
        )
    }

    func testWhenMultipleInitialResourcesComplete_thenMetricValueReflectsLastCompletedResource() throws {
        // Given
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        let t0 = viewStartDate // initial resource
        let t1 = viewStartDate + t100ms * 0.33 // initial resource
        let t2 = viewStartDate + t100ms * 0.66 // initial resource
        metric.trackResourceStart(at: t0, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceStart(at: t1, resourceID: .resource2, resourceURL: .mockAny())
        metric.trackResourceStart(at: t2, resourceID: .resource3, resourceURL: .mockAny())

        // When
        let durations: [TimeInterval] = [10, 15, 20].shuffled()
        metric.trackResourceEnd(at: t0 + durations[0], resourceID: .resource1, resourceDuration: nil)
        metric.trackResourceEnd(at: t0 + durations[1], resourceID: .resource2, resourceDuration: nil)
        metric.trackResourceEnd(at: t0 + durations[2], resourceID: .resource3, resourceDuration: nil)

        // Then
        let ttns = try metric.value(with: .mockAppInForeground(since: t0)).get()
        XCTAssertEqual(ttns, durations.max()!, accuracy: 0.01, "Metric value should reflect the completion of the last initial resource.")
    }

    func testWhenNewInitialResourceStartsAfterPreviousComplete_thenMetricValueIsUpdated() throws {
        // Given
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        let t0 = viewStartDate
        let t1 = viewStartDate + t100ms * 0.33
        let t2 = viewStartDate + t100ms * 0.66
        let duration: TimeInterval = t100ms * 0.25

        // When (complete first initial resource)
        metric.trackResourceStart(at: t0, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: t0 + duration, resourceID: .resource1, resourceDuration: duration)
        let ttns1A = try metric.value(with: .mockAppInForeground(since: t0)).get()

        // When (complete next initial resource)
        metric.trackResourceStart(at: t1, resourceID: .resource2, resourceURL: .mockAny())
        let ttns1B = try metric.value(with: .mockAppInForeground(since: t0)).get() // caught error: "initialResourcesIncomplete"
        metric.trackResourceEnd(at: t1 + duration, resourceID: .resource2, resourceDuration: duration)
        let ttns2A = try metric.value(with: .mockAppInForeground(since: t0)).get()

        // When (complete next initial resource)
        metric.trackResourceStart(at: t2, resourceID: .resource3, resourceURL: .mockAny())
        let ttns2B = try metric.value(with: .mockAppInForeground(since: t0)).get()
        metric.trackResourceEnd(at: t2 + duration, resourceID: .resource3, resourceDuration: duration)
        let ttns3 = try metric.value(with: .mockAppInForeground(since: t0)).get()

        // Then
        XCTAssertEqual(ttns1A, t100ms * 0.25, accuracy: 0.01)
        XCTAssertEqual(ttns1B, ttns1A, accuracy: 0.01)
        XCTAssertEqual(ttns2A, t100ms * 0.58, accuracy: 0.01)
        XCTAssertEqual(ttns2B, ttns2A, accuracy: 0.01)
        XCTAssertEqual(ttns3, t100ms * 0.91, accuracy: 0.01)
    }

    // MARK: - Metric Value vs Resource Dropped

    func testWhenAllResourcesAreDropped_thenMetricValueIsNotAvailable() {
        // Given
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource2, resourceURL: .mockAny())
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource3, resourceURL: .mockAny())

        // When
        metric.trackResourceDropped(resourceID: .resource1)
        metric.trackResourceDropped(resourceID: .resource2)
        metric.trackResourceDropped(resourceID: .resource3)

        // Then
        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: viewStartDate)), .failure(.initialResourcesDropped))
    }

    func testWhenSomeResourcesAreDropped_thenMetricValueReflectsCompletedResources() throws {
        // Given
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource2, resourceURL: .mockAny())
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource3, resourceURL: .mockAny())

        // When
        metric.trackResourceEnd(at: viewStartDate + 1.42, resourceID: .resource1, resourceDuration: nil)
        metric.trackResourceDropped(resourceID: .resource2)
        metric.trackResourceDropped(resourceID: .resource3)

        // Then
        let ttns = try metric.value(with: .mockAppInForeground(since: viewStartDate)).get()
        XCTAssertEqual(ttns, 1.42, accuracy: 0.01, "Metric value should reflect completed resources.")
    }

    // MARK: - "View Stopped" Condition

    func testWhenViewIsStopped_thenMetricValueIsNotAvailable() {
        // Given
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)

        // When
        metric.trackViewWasStopped()

        // Then
        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: viewStartDate)), .failure(.noTrackedResources))

        // When
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: nil)

        // Then
        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: viewStartDate)), .failure(.noTrackedResources))
    }

    func testWhenViewIsStoppedBeforeResourceCompletes_thenMetricValueIsNotAvailable() {
        // Given
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())

        // When
        metric.trackViewWasStopped()
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: nil)

        // Then
        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: viewStartDate)), .failure(.viewStoppedBeforeSettled))
    }

    func testWhenViewIsStoppedAfterResourceCompletes_thenMetricValueIsAvailable() throws {
        // Given
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: nil)

        // When
        metric.trackViewWasStopped()

        // Then
        let ttns = try metric.value(with: .mockAppInForeground(since: viewStartDate)).get()
        XCTAssertEqual(ttns, 1, accuracy: 0.01, "Metric value should be available if view is stopped after resource completes.")
    }

    // MARK: - "App State" Condition

    func testWhenAppStaysActiveDuringViewLoading_thenMetricValueIsAvailable() throws {
        // Given
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        let resourceStart = viewStartDate
        let resourceEnd = resourceStart + 5
        metric.trackResourceStart(at: resourceStart, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: resourceEnd, resourceID: .resource1, resourceDuration: nil)

        // When
        let appStateHistory = AppStateHistory(initialState: .active, date: .distantPast)

        // Then
        let ttns = try metric.value(with: appStateHistory).get()
        XCTAssertEqual(ttns, 5, accuracy: 0.01, "Metric value should be available if app remains active during view loading.")
    }

    func testWhenAppDoesNotStayActiveDuringViewLoading_thenMetricValueIsNotAvailable() {
        // Given
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        let resourceStart = viewStartDate
        let resourceDuration: TimeInterval = 5
        let resourceEnd = resourceStart + resourceDuration
        metric.trackResourceStart(at: resourceStart, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: resourceEnd, resourceID: .resource1, resourceDuration: resourceDuration)

        // When
        var appStateHistory = AppStateHistory(initialState: .active, date: .distantPast)
        appStateHistory.append(state: [.inactive, .background].randomElement()!, at: resourceStart + resourceDuration * 0.25)
        appStateHistory.append(state: .active, at: resourceStart + resourceDuration * 0.5)

        // Then
        XCTAssertEqual(metric.value(with: appStateHistory), .failure(.appNotInForeground))
    }

    // MARK: - Edge Cases

    func testWhenNoResourcesAreTracked() {
        let metric = createMetric(viewStartDate: Date(), resourcePredicate: mockAllInitialResourcesPredicate)
        XCTAssertEqual(metric.value(with: .mockRandom()), .failure(.noTrackedResources))
    }

    func testWhenResourceEndsBeforeViewStarts() {
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate - 2, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: viewStartDate - 1, resourceID: .resource1, resourceDuration: nil)
        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: .distantPast)), .failure(.noInitialResources))
    }

    func testWhenResourceEndsThenStarts() {
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: nil)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())
        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: .distantPast)), .failure(.initialResourcesIncomplete))
    }

    func testWhenResourceEndsEarlierThanItStarts() {
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate + 1, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: viewStartDate + 0.5, resourceID: .resource1, resourceDuration: nil)
        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: .distantPast)), .failure(.initialResourcesInvalid))
    }

    func testWhenResourceEndsImmediately() throws {
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        let t0 = viewStartDate + t100ms * 0.5
        metric.trackResourceStart(at: t0, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: t0, resourceID: .resource1, resourceDuration: nil)

        let ttns = try metric.value(with: .mockAppInForeground(since: .distantPast)).get()
        XCTAssertEqual(ttns, t100ms * 0.5, accuracy: 0.01, "Metric value should be equal to resource start offset.")
    }

    func testWhenResourceEndsWithNegativeDuration() throws {
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: -10)
        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: .distantPast)), .failure(.initialResourcesInvalid))
    }

    func testWhenSomeResourceEndsWithNegativeDuration() throws {
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: nil)

        metric.trackResourceStart(at: viewStartDate + 1, resourceID: .resource2, resourceURL: .mockAny())
        metric.trackResourceEnd(at: viewStartDate + 2, resourceID: .resource2, resourceDuration: -10)

        let ttns = try metric.value(with: .mockAppInForeground(since: .distantPast)).get()
        XCTAssertEqual(ttns, 1, accuracy: 0.01)
    }

    func testWhenResourceEndsImmediatelyWithDuration() throws {
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        let t0 = viewStartDate + t100ms * 0.5
        let duration: TimeInterval = 10
        metric.trackResourceStart(at: t0, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: t0, resourceID: .resource1, resourceDuration: duration)

        let ttns = try metric.value(with: .mockAppInForeground(since: .distantPast)).get()
        XCTAssertEqual(ttns, duration + t100ms * 0.5, accuracy: 0.01, "Metric value should be equal to resource duration plus resource start offset.")
    }

    func testWhenResourceIsDropped() throws {
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceDropped(resourceID: .resource1)

        XCTAssertEqual(metric.value(with: .mockAppInForeground(since: .distantPast)), .failure(.initialResourcesDropped))
    }

    func testWhenSomeResourcesAreDropped() throws {
        let metric = createMetric(viewStartDate: viewStartDate, resourcePredicate: mockAllInitialResourcesPredicate)
        metric.trackResourceStart(at: viewStartDate, resourceID: .resource1, resourceURL: .mockAny())
        metric.trackResourceEnd(at: viewStartDate + 1, resourceID: .resource1, resourceDuration: nil)

        metric.trackResourceStart(at: viewStartDate, resourceID: .resource2, resourceURL: .mockAny())
        metric.trackResourceDropped(resourceID: .resource2)

        let ttns = try metric.value(with: .mockAppInForeground(since: .distantPast)).get()
        XCTAssertEqual(ttns, 1, accuracy: 0.01)
    }
}
